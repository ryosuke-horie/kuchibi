import AppKit
import CoreGraphics
import os

/// クリップボード操作とキーストロークシミュレーション
final class ClipboardServiceImpl: ClipboardServicing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "Clipboard")

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            Self.logger.info("テキストをクリップボードにコピー")
        } else {
            Self.logger.error("クリップボードへのコピーに失敗")
        }
    }

    // Cmd+V が対象アプリに到達するまでの経験的な待機時間
    private static let clipboardRestoreDelay: Duration = .milliseconds(200)

    func pasteToActiveApp(text: String, restoreClipboard: Bool) async {
        let pasteboard = NSPasteboard.general

        // 1st try: AXUIElement 経由でフォーカス中の要素にテキストを直接挿入
        let insertedViaAXUI = await MainActor.run { insertTextViaAXUI(text) }
        if insertedViaAXUI {
            Self.logger.info("AXUIElement経由でテキストを直接挿入")
            if !restoreClipboard {
                copyToClipboard(text: text)
            }
            return
        }
        Self.logger.debug("AXUIElement挿入失敗: クリップボード+Cmd+Vを試みる")

        // 2nd try: クリップボード経由でCmd+V
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = restoreClipboard
            ? pasteboard.pasteboardItems?.flatMap { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            } ?? []
            : []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Self.logger.error("クリップボードへの書き込みに失敗: ペーストを中断")
            restoreItems(savedItems, to: pasteboard)
            return
        }

        // AppleScript (System Events) 経由でCmd+V を送信（最も信頼性が高い）
        // 初回実行時に Automation 権限ダイアログが表示される
        let pasteSucceeded = sendPasteViaAppleScript()

        if pasteSucceeded {
            if restoreClipboard {
                try? await Task.sleep(for: Self.clipboardRestoreDelay)
                pasteboard.clearContents()
                restoreItems(savedItems, to: pasteboard)
            }
            Self.logger.info("AppleScript経由でCmd+Vを送信")
        } else {
            // フォールバック: CGEvent
            Self.logger.warning("AppleScript失敗: CGEventにフォールバック")
            let cgSucceeded = await MainActor.run { sendPasteKeyEventViaCGEvent() }
            if cgSucceeded {
                if restoreClipboard {
                    try? await Task.sleep(for: Self.clipboardRestoreDelay)
                    pasteboard.clearContents()
                    restoreItems(savedItems, to: pasteboard)
                }
                Self.logger.info("CGEvent経由でCmd+Vを送信")
            } else {
                if restoreClipboard {
                    pasteboard.clearContents()
                    restoreItems(savedItems, to: pasteboard)
                    Self.logger.warning("ペースト失敗: クリップボードを元の内容に復元しました")
                } else {
                    Self.logger.warning("ペースト失敗: テキストはクリップボードに残しました")
                }
            }
        }
    }

    // MARK: - Private

    private func restoreItems(_ items: [(NSPasteboard.PasteboardType, Data)], to pasteboard: NSPasteboard) {
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }

    /// AXUIElement 経由でフォーカス中の要素へテキストを直接挿入
    @MainActor
    private func insertTextViaAXUI(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard copyResult == .success, let rawElement = focusedElement else {
            Self.logger.debug("AXUIElement: フォーカス要素の取得に失敗 (\(copyResult.rawValue))")
            return false
        }
        // swiftlint:disable:next force_cast
        let element = rawElement as! AXUIElement
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if setResult == .success {
            return true
        }
        Self.logger.debug("AXUIElement: kAXSelectedTextAttribute 書き込み失敗 (\(setResult.rawValue))")
        return false
    }

    /// System Events (AppleScript) 経由で Cmd+V を送信
    private func sendPasteViaAppleScript() -> Bool {
        let source = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            Self.logger.warning("AppleScript実行エラー: \(error)")
            return false
        }
        return true
    }

    /// CGEvent 経由で Cmd+V を送信（最終フォールバック）
    @MainActor
    @discardableResult
    private func sendPasteKeyEventViaCGEvent() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            Self.logger.error("CGEventの作成に失敗: アクセシビリティ権限を確認してください")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
