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
            try? await Task.sleep(for: .milliseconds(200))

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

        // 安全策: 先にクリップボードにコピーしておく（失敗時に手動ペースト可能）
        copyToClipboard(text: text)

        // 事前チェック: CGEvent 生成が可能か確認（アクセシビリティ権限等）
        guard CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) != nil else {
            Self.logger.error("CGEvent生成失敗: アクセシビリティ権限を確認してください。フォールバックでペースト入力に切り替え")
            await pasteToActiveApp(text: text)
            return
        }

        for (index, char) in text.enumerated() {
            let utf16 = Array(String(char).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                // 途中失敗時は pasteToActiveApp へのフォールバックを行わない
                // 理由: 既にタイプ済みの文字があるため、ペーストするとテキストが重複する
                // テキストはクリップボードに残してあるので手動ペーストで対応可能
                Self.logger.error("CGEvent生成が途中で失敗（\(index)/\(text.count)文字目）。テキストはクリップボードに残しました")
                return
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            try? await Task.sleep(for: .milliseconds(2))
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
