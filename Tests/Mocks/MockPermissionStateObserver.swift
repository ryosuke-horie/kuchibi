import Combine
@testable import Kuchibi

/// `PermissionStateObserving` のテスト用モック。
@MainActor
final class MockPermissionStateObserver: ObservableObject, PermissionStateObserving {
    @Published var microphoneGranted: Bool
    @Published var accessibilityTrusted: Bool

    private(set) var refreshCallCount = 0

    init(microphoneGranted: Bool = false, accessibilityTrusted: Bool = false) {
        self.microphoneGranted = microphoneGranted
        self.accessibilityTrusted = accessibilityTrusted
    }

    func refresh() {
        refreshCallCount += 1
    }
}
