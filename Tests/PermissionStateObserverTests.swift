import Foundation
import Testing
@testable import Kuchibi

@Suite("PermissionStateObserver")
@MainActor
struct PermissionStateObserverTests {
    @Test("両方の権限が granted のとき Published 値も true")
    func bothGranted() {
        let observer = PermissionStateObserver(
            fetchMicrophoneStatus: { true },
            fetchAccessibilityTrusted: { true }
        )
        // init() 内で refresh() が走るため即時に値が反映される
        #expect(observer.microphoneGranted)
        #expect(observer.accessibilityTrusted)
    }

    @Test("両方の権限が denied のとき Published 値も false")
    func bothDenied() {
        let observer = PermissionStateObserver(
            fetchMicrophoneStatus: { false },
            fetchAccessibilityTrusted: { false }
        )
        #expect(!observer.microphoneGranted)
        #expect(!observer.accessibilityTrusted)
    }

    @Test("refresh() で状態変化を再取得して Published に反映する")
    func refreshPropagatesStateChange() {
        var micValue = false
        var axValue = false
        let observer = PermissionStateObserver(
            fetchMicrophoneStatus: { micValue },
            fetchAccessibilityTrusted: { axValue }
        )
        #expect(!observer.microphoneGranted)
        #expect(!observer.accessibilityTrusted)

        micValue = true
        axValue = true
        observer.refresh()

        #expect(observer.microphoneGranted)
        #expect(observer.accessibilityTrusted)
    }
}
