@testable import Kuchibi

final class MockEscapeKeyMonitor: EscapeKeyMonitoring {
    private(set) var isMonitoring: Bool = false
    private(set) var startMonitoringCallCount: Int = 0
    private(set) var stopMonitoringCallCount: Int = 0

    private var onEscapeCallback: (() -> Void)?

    func startMonitoring(onEscape: @escaping () -> Void) {
        isMonitoring = true
        startMonitoringCallCount += 1
        onEscapeCallback = onEscape
    }

    func stopMonitoring() {
        isMonitoring = false
        stopMonitoringCallCount += 1
        onEscapeCallback = nil
    }

    func simulateEscapeKey() {
        onEscapeCallback?()
    }
}
