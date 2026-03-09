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

        // 元のクリップボード内容を退避（復元が必要な場合のみ、複数型を全て保存）
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = restoreClipboard
            ? pasteboard.pasteboardItems?.flatMap { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            } ?? []
            : []

        // テキストをクリップボードに設定
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Self.logger.error("クリップボードへの書き込みに失敗: ペーストを中断")
            restoreItems(savedItems, to: pasteboard)
            return
        }

        // Cmd+V を送信（成否はイベント到達を保証しない）
        let pasteSucceeded = sendPasteKeyEvent()

        if pasteSucceeded {
            if restoreClipboard {
                // 短い遅延後にクリップボード復元
                try? await Task.sleep(for: Self.clipboardRestoreDelay)
                pasteboard.clearContents()
                restoreItems(savedItems, to: pasteboard)
            }
            Self.logger.info("テキストをアクティブアプリに直接入力")
        } else {
            if restoreClipboard {
                // ペースト失敗時も元の内容を復元する
                pasteboard.clearContents()
                restoreItems(savedItems, to: pasteboard)
                Self.logger.warning("ペースト失敗: クリップボードを元の内容に復元しました")
            } else {
                Self.logger.warning("ペースト失敗: テキストはクリップボードに残しました")
            }
        }
    }

    private func restoreItems(_ items: [(NSPasteboard.PasteboardType, Data)], to pasteboard: NSPasteboard) {
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }

    @discardableResult
    private func sendPasteKeyEvent() -> Bool {
        // Cmd+V のキーコード: V = 0x09
        // hidSystemState をソースにすることで OS がキーストロークを正規の入力として扱う
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            Self.logger.error("CGEventの作成に失敗: アクセシビリティ権限を確認してください")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // cgAnnotatedSessionEventTap はフロントモストアプリに確実に届く
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
