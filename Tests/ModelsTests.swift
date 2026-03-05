import Foundation
import Testing
@testable import Kuchibi

// MARK: - SessionState Tests

@Suite("SessionState")
struct SessionStateTests {
    @Test("全ケースが定義されている")
    func allCasesExist() {
        let idle = SessionState.idle
        let recording = SessionState.recording
        let processing = SessionState.processing

        #expect(idle != recording)
        #expect(recording != processing)
        #expect(idle != processing)
    }

    @Test("Equatableに準拠")
    func equatable() {
        #expect(SessionState.idle == SessionState.idle)
        #expect(SessionState.recording == SessionState.recording)
        #expect(SessionState.processing == SessionState.processing)
    }
}

// MARK: - OutputMode Tests

@Suite("OutputMode")
struct OutputModeTests {
    @Test("全ケースが定義されている")
    func allCasesExist() {
        let clipboard = OutputMode.clipboard
        let directInput = OutputMode.directInput
        let autoInput = OutputMode.autoInput

        #expect(clipboard != directInput)
        #expect(clipboard != autoInput)
        #expect(directInput != autoInput)
    }

    @Test("Equatableに準拠")
    func equatable() {
        #expect(OutputMode.clipboard == OutputMode.clipboard)
        #expect(OutputMode.directInput == OutputMode.directInput)
        #expect(OutputMode.autoInput == OutputMode.autoInput)
    }

    @Test("rawValueによるUserDefaults永続化サポート")
    func rawValue() {
        #expect(OutputMode.clipboard.rawValue == "clipboard")
        #expect(OutputMode.directInput.rawValue == "directInput")
        #expect(OutputMode.autoInput.rawValue == "autoInput")
        #expect(OutputMode(rawValue: "clipboard") == .clipboard)
        #expect(OutputMode(rawValue: "directInput") == .directInput)
        #expect(OutputMode(rawValue: "autoInput") == .autoInput)
        #expect(OutputMode(rawValue: "invalid") == nil)
    }
}

// MARK: - KuchibiError Tests

@Suite("KuchibiError")
struct KuchibiErrorTests {
    @Test("modelLoadFailed は underlying error を保持する")
    func modelLoadFailed() {
        let underlying = NSError(domain: "test", code: 1)
        let error = KuchibiError.modelLoadFailed(underlying: underlying)

        if case .modelLoadFailed(let inner) = error {
            #expect((inner as NSError).domain == "test")
        } else {
            Issue.record("Expected modelLoadFailed")
        }
    }

    @Test("microphonePermissionDenied")
    func microphonePermissionDenied() {
        let error = KuchibiError.microphonePermissionDenied
        if case .microphonePermissionDenied = error {
            // OK
        } else {
            Issue.record("Expected microphonePermissionDenied")
        }
    }

    @Test("microphoneUnavailable")
    func microphoneUnavailable() {
        let error = KuchibiError.microphoneUnavailable
        if case .microphoneUnavailable = error {
            // OK
        } else {
            Issue.record("Expected microphoneUnavailable")
        }
    }

    @Test("recognitionFailed は underlying error を保持する")
    func recognitionFailed() {
        let underlying = NSError(domain: "asr", code: 42)
        let error = KuchibiError.recognitionFailed(underlying: underlying)

        if case .recognitionFailed(let inner) = error {
            #expect((inner as NSError).code == 42)
        } else {
            Issue.record("Expected recognitionFailed")
        }
    }

    @Test("accessibilityPermissionDenied")
    func accessibilityPermissionDenied() {
        let error = KuchibiError.accessibilityPermissionDenied
        if case .accessibilityPermissionDenied = error {
            // OK
        } else {
            Issue.record("Expected accessibilityPermissionDenied")
        }
    }

    @Test("silenceTimeout")
    func silenceTimeout() {
        let error = KuchibiError.silenceTimeout
        if case .silenceTimeout = error {
            // OK
        } else {
            Issue.record("Expected silenceTimeout")
        }
    }

    @Test("Error プロトコルに準拠")
    func conformsToError() {
        let error: any Error = KuchibiError.silenceTimeout
        #expect(error is KuchibiError)
    }
}
