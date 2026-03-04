import Foundation
@testable import Kuchibi

final class MockSessionMonitoringService: SessionMonitoring {
    var sessionStartedCalls = 0
    var textCompletedCalls: [String] = []
    var sessionEndedCalls = 0
    var sessionFailedCalls: [KuchibiError] = []

    func sessionStarted() {
        sessionStartedCalls += 1
    }

    func textCompleted(text: String) {
        textCompletedCalls.append(text)
    }

    func sessionEnded() {
        sessionEndedCalls += 1
    }

    func sessionFailed(error: KuchibiError) {
        sessionFailedCalls.append(error)
    }
}
