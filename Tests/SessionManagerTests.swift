import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

@Suite("SessionManager")
struct SessionManagerTests {
    @Test("初期状態はidle")
    func initialState() async {
        let sm = await createSessionManager()
        let state = await sm.state
        #expect(state == .idle)
    }

    @Test("startSessionでrecordingに遷移する")
    func startSession() async {
        let sm = await createSessionManager()
        await sm.startSession()

        let state = await sm.state
        #expect(state == .recording)
    }

    @Test("stopSessionでidleに遷移する")
    func stopSession() async throws {
        let sm = await createSessionManager()
        await sm.startSession()
        await sm.stopSession()

        // processing → idle の遷移を待つ
        try await Task.sleep(for: .milliseconds(100))
        let state = await sm.state
        #expect(state == .idle)
    }

    @Test("idle以外ではstartSessionが無視される")
    func startSessionWhenNotIdle() async {
        let sm = await createSessionManager()
        await sm.startSession()
        let stateBefore = await sm.state
        #expect(stateBefore == .recording)

        // 2回目のstartSessionは無視
        await sm.startSession()
        let stateAfter = await sm.state
        #expect(stateAfter == .recording)
    }

    @Test("stopSession後にOutputManagerが呼ばれる")
    func outputCalledAfterStop() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "認識結果"))
        ]
        let sm = await createSessionManager(outputManager: mockOutput, speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        #expect(!mockOutput.outputCalls.isEmpty)
        #expect(mockOutput.outputCalls.first?.text == "認識結果")
    }

    @Test("outputModeのデフォルトはclipboard")
    func defaultOutputMode() async {
        let sm = await createSessionManager()
        let mode = await sm.outputMode
        #expect(mode == .clipboard)
    }

    // MARK: - Helper

    private func createSessionManager(
        audioService: AudioCapturing? = nil,
        outputManager: OutputManaging? = nil,
        speechService: SpeechRecognizing? = nil,
        notificationService: NotificationServicing? = nil
    ) async -> SessionManagerImpl {
        let audio = audioService ?? MockAudioCaptureService()
        let asr: SpeechRecognizing
        if let s = speechService {
            asr = s
        } else {
            let mock = MockSpeechRecognitionService()
            mock.isModelLoaded = true
            asr = mock
        }
        let output = outputManager ?? MockOutputManager()
        let notification = notificationService ?? MockNotificationService()
        return await SessionManagerImpl(
            audioService: audio,
            speechService: asr,
            outputManager: output,
            notificationService: notification
        )
    }
}
