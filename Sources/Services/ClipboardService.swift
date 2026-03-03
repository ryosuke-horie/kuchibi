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
        sendPasteKeyEvent()

        // 短い遅延後にクリップボード復元
        try? await Task.sleep(for: .milliseconds(100))

        pasteboard.clearContents()
        for (type, data) in savedItems {
            pasteboard.setData(data, forType: type)
        }

        Self.logger.info("テキストをアクティブアプリに直接入力")
    }

    private func sendPasteKeyEvent() {
        // Cmd+V のキーコード: V = 0x09
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
