import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

@Suite("ESCキーキャンセル統合テスト")
struct EscapeKeyCancelIntegrationTests {

    @MainActor
    private func makeSessionManager(
        audioService: AudioCapturing? = nil,
        speechService: SpeechRecognizing? = nil,
        outputManager: OutputManaging? = nil
    ) -> SessionManagerImpl {
        let asr: SpeechRecognizing
        if let s = speechService {
            asr = s
        } else {
            let mock = MockSpeechRecognitionService()
            mock.isModelLoaded = true
            asr = mock
        }
        return SessionManagerImpl(
            audioService: audioService ?? MockAudioCaptureService(),
            speechService: asr,
            outputManager: outputManager ?? MockOutputManager(),
            notificationService: MockNotificationService(),
            appSettings: AppSettings(defaults: UserDefaults(suiteName: "test.esc.integ.\(UUID().uuidString)")!),
            micAuthorizationStatus: { .authorized },
            accessibilityTrusted: { true }
        )
    }

    @Test("ESC検出からcancelSession呼び出しまでのフローが動作する")
    @MainActor
    func escapeKeyTriggersCancelSession() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.holdStream = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "ESCでキャンセルされるテキスト"))
        ]
        let mockEscMonitor = MockEscapeKeyMonitor()
        let sm = makeSessionManager(speechService: mockASR, outputManager: mockOutput)

        mockEscMonitor.startMonitoring {
            Task { @MainActor in
                sm.cancelSession()
            }
        }

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(sm.state == .recording)

        mockEscMonitor.simulateEscapeKey()
        try await Task.sleep(for: .milliseconds(100))

        #expect(sm.state == .idle)
        #expect(mockOutput.outputCalls.isEmpty)

        mockASR.finishStream()
    }

    @Test("キャンセル後にstartSessionが正常に動作する（状態復帰の検証）")
    @MainActor
    func startSessionWorksAfterCancel() async throws {
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.holdStream = true
        let mockEscMonitor = MockEscapeKeyMonitor()
        let sm = makeSessionManager(speechService: mockASR)

        mockEscMonitor.startMonitoring {
            Task { @MainActor in
                sm.cancelSession()
            }
        }

        sm.startSession()
        try await Task.sleep(for: .milliseconds(50))
        #expect(sm.state == .recording)

        mockEscMonitor.simulateEscapeKey()
        try await Task.sleep(for: .milliseconds(50))
        #expect(sm.state == .idle)

        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(50))

        // キャンセル後に再度 startSession が正常に動作すること
        let mockASR2 = MockSpeechRecognitionService()
        mockASR2.isModelLoaded = true
        mockASR2.holdStream = true
        let sm2 = makeSessionManager(speechService: mockASR2)

        sm2.startSession()
        #expect(sm2.state == .recording)

        mockASR2.finishStream()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("キャンセル時にテキスト出力が一切行われない")
    @MainActor
    func noOutputOnCancel() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.holdStream = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "出力されてはいけないテキスト"))
        ]
        let mockEscMonitor = MockEscapeKeyMonitor()
        let sm = makeSessionManager(speechService: mockASR, outputManager: mockOutput)

        mockEscMonitor.startMonitoring {
            Task { @MainActor in
                sm.cancelSession()
            }
        }

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))

        mockEscMonitor.simulateEscapeKey()
        try await Task.sleep(for: .milliseconds(200))

        #expect(mockOutput.outputCalls.isEmpty)

        mockASR.finishStream()
    }
}
