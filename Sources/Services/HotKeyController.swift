import Carbon
import HotKey
import os

/// グローバルホットキーの登録・トグル制御
final class HotKeyControllerImpl: HotKeyControlling {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "HotKey")

    private var hotKey: HotKey?
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func register() {
        // デフォルト: Cmd+Shift+Space
        hotKey = HotKey(key: .space, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            Self.logger.info("ホットキーが押下された")
            self?.onToggle()
        }
        Self.logger.info("グローバルホットキーを登録: Cmd+Shift+Space")
    }

    func unregister() {
        hotKey = nil
        Self.logger.info("グローバルホットキーを解除")
    }
}
