import AppKit
import CoreGraphics
import os

/// クリップボード操作とキーストロークシミュレーション
final class ClipboardServiceImpl: ClipboardServicing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "Clipboard")

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Self.logger.info("テキストをクリップボードにコピー")
    }

    func pasteToActiveApp(text: String) async {
        let pasteboard = NSPasteboard.general

        // 元のクリップボード内容を退避
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        // テキストをクリップボードに設定
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Cmd+V を送信
        let pasteSucceeded = sendPasteKeyEvent()

        if pasteSucceeded {
            // 短い遅延後にクリップボード復元
            try? await Task.sleep(for: .milliseconds(100))

            pasteboard.clearContents()
            for (type, data) in savedItems {
                pasteboard.setData(data, forType: type)
            }
            Self.logger.info("テキストをアクティブアプリに直接入力")
        } else {
            // ペースト失敗時はテキストをクリップボードに残す
            Self.logger.warning("ペースト失敗: テキストはクリップボードに残しました")
        }
    }

    func typeText(_ text: String) async {
        guard !text.isEmpty else { return }

        for char in text {
            let utf16 = Array(String(char).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                Self.logger.warning("CGEvent生成失敗: フォールバックでペースト入力に切り替え")
                await pasteToActiveApp(text: text)
                return
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        Self.logger.info("直接タイピング入力完了")
    }

    @discardableResult
    private func sendPasteKeyEvent() -> Bool {
        // Cmd+V のキーコード: V = 0x09
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else {
            Self.logger.error("CGEventの作成に失敗: アクセシビリティ権限を確認してください")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
