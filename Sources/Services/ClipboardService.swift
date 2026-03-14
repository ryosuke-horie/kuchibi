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

    // 1文字ずつキーイベント送信する際の間隔
    private static let typeCharDelay: Duration = .milliseconds(5)

    func typeText(_ text: String) async {
        let success = await MainActor.run { sendTextViaCGEventUnicode(text) }
        if success {
            Self.logger.info("CGEvent Unicode経由でテキストを直接入力")
            return
        }
        Self.logger.warning("CGEvent Unicode入力失敗: クリップボード+ペーストにフォールバック")
        await pasteToActiveApp(text: text, restoreClipboard: true)
    }

    func runDiagnostics() async -> String {
        var report = "=== Kuchibi 入力診断レポート ===\n"
        report += "日時: \(Date())\n\n"

        let trusted = AXIsProcessTrusted()
        report += "[権限] AXIsProcessTrusted: \(trusted)\n\n"

        // AXUIElement テスト
        let axResult = await MainActor.run { () -> String in
            let systemWide = AXUIElementCreateSystemWide()
            var focusedElement: AnyObject?
            let copyResult = AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement
            )
            if copyResult != .success {
                return "フォーカス要素取得失敗 (error: \(copyResult.rawValue))"
            }
            guard let element = focusedElement else { return "フォーカス要素がnil" }
            // swiftlint:disable:next force_cast
            let axElement = element as! AXUIElement
            var role: AnyObject?
            AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
            return "フォーカス要素取得成功 (role: \(role as? String ?? "不明"))"
        }
        report += "[AXUIElement] \(axResult)\n"

        // CGEvent 生成テスト
        let cgResult = await MainActor.run { () -> String in
            let source = CGEventSource(stateID: .combinedSessionState)
            if source == nil { return "CGEventSource生成失敗" }
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return "CGEvent生成失敗"
            }
            _ = event
            return "CGEvent生成成功"
        }
        report += "[CGEvent] \(cgResult)\n"

        // AppleScript テスト（実行はしない）
        let scriptTest = NSAppleScript(source: "return \"ok\"")
        var errorInfo: NSDictionary?
        let scriptResult = scriptTest?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            report += "[AppleScript] 実行エラー: \(error)\n"
        } else {
            report += "[AppleScript] 基本実行: OK (result: \(scriptResult?.stringValue ?? "nil"))\n"
        }

        // System Events アクセステスト
        let seScript = NSAppleScript(source: """
            tell application "System Events"
                return name of first process whose frontmost is true
            end tell
        """)
        var seError: NSDictionary?
        let seResult = seScript?.executeAndReturnError(&seError)
        if let error = seError {
            report += "[System Events] アクセス失敗: \(error)\n"
        } else {
            report += "[System Events] アクセス成功 (frontmost: \(seResult?.stringValue ?? "不明"))\n"
        }

        report += "\n=== 診断完了 ===\n"

        // ファイルに保存
        let path = NSHomeDirectory() + "/Desktop/kuchibi-diag.txt"
        try? report.write(toFile: path, atomically: true, encoding: .utf8)
        Self.logger.info("診断レポートを保存: \(path)")

        return report
    }

    // MARK: - Private

    private func restoreItems(_ items: [(NSPasteboard.PasteboardType, Data)], to pasteboard: NSPasteboard) {
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }

    /// CGEvent + keyboardSetUnicodeString 経由で Unicode テキストを直接入力
    @MainActor
    private func sendTextViaCGEventUnicode(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            let utf16 = Array(String(scalar).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                Self.logger.error("CGEvent Unicode: イベント生成に失敗")
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
        return true
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
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            Self.logger.error("CGEventの作成に失敗: アクセシビリティ権限を確認してください")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}
