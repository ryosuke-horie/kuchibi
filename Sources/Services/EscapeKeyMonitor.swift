import AppKit
import os

/// NSEvent グローバルモニターで ESC キーを監視する実装
final class EscapeKeyMonitorImpl: EscapeKeyMonitoring {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "EscapeKeyMonitor")
    private static let escKeyCode: UInt16 = 53

    private var monitor: Any?

    func startMonitoring(onEscape: @escaping () -> Void) {
        if monitor != nil {
            stopMonitoring()
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == EscapeKeyMonitorImpl.escKeyCode else { return }
            onEscape()
        }
        if monitor == nil {
            Self.logger.error("ESCキーのグローバルモニター登録に失敗した。ESCキャンセル機能は無効です")
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
