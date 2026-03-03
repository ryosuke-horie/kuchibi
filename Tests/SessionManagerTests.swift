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

    @Test("idle状態でstopSessionは無視される")
    func stopSessionWhenIdle() async {
        let sm = await createSessionManager()
        await sm.stopSession()
        let state = await sm.state
        #expect(state == .idle)
    }

    @Test("stopSession後にOutputManagerが呼ばれる")
    func outputCalledAfterStop() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "認識結果"))
        ]
        let sm = await createSessionManager(outputManager: mockOutput, speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        #expect(!mockOutput.outputCalls.isEmpty)
        #expect(mockOutput.outputCalls.first?.text == "認識結果")
        #expect(mockOutput.outputCalls.first?.mode == .clipboard)
    }

    @Test("outputModeのデフォルトはclipboard")
    func defaultOutputMode() async {
        let sm = await createSessionManager()
        let mode = await sm.outputMode
        #expect(mode == .clipboard)
    }

    @Test("toggleSessionでセッションの開始・停止が切り替わる")
    func toggleSession() async throws {
        let sm = await createSessionManager()

        // idle → recording
        await sm.toggleSession()
        #expect(await sm.state == .recording)

        // recording → processing → idle
        await sm.toggleSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await sm.state == .idle)
    }

    @Test("textChangedイベントでpartialTextが更新される")
    func partialTextUpdated() async throws {
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .textChanged(partial: "途中テキスト")),
            RecognitionEvent(kind: .lineCompleted(final: "完了テキスト"))
        ]
        let sm = await createSessionManager(speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        let partial = await sm.partialText
        #expect(partial == "途中テキスト")
    }

    @Test("モデル未読み込みではstartSessionが拒否される")
    func startSessionModelNotLoaded() async throws {
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = false
        let mockNotification = MockNotificationService()
        let sm = await createSessionManager(speechService: mockASR, notificationService: mockNotification)

        await sm.startSession()
        #expect(await sm.state == .idle)

        try await Task.sleep(for: .milliseconds(50))
        #expect(mockNotification.sentErrors.count == 1)
        if case .modelLoadFailed = mockNotification.sentErrors.first {} else {
            Issue.record("modelLoadFailedを期待したが \(String(describing: mockNotification.sentErrors.first)) を受信")
        }
    }

    @Test("キャプチャ失敗ではstartSessionがidleのまま")
    func startSessionCaptureFailure() async throws {
        let mockAudio = MockAudioCaptureService()
        mockAudio.shouldThrowOnStart = true
        let mockNotification = MockNotificationService()
        let sm = await createSessionManager(audioService: mockAudio, notificationService: mockNotification)

        await sm.startSession()
        #expect(await sm.state == .idle)

        try await Task.sleep(for: .milliseconds(50))
        #expect(mockNotification.sentErrors.count == 1)
        if case .microphoneUnavailable = mockNotification.sentErrors.first {} else {
            Issue.record("microphoneUnavailableを期待したが \(String(describing: mockNotification.sentErrors.first)) を受信")
        }
    }

    @Test("processing状態でtoggleSessionは無視される")
    func toggleSessionDuringProcessing() async throws {
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.holdStream = true
        let sm = await createSessionManager(speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        // holdStream=true なのでイベントストリームは終了しない → processingのまま
        #expect(await sm.state == .processing)

        await sm.toggleSession()
        #expect(await sm.state == .processing)

        // クリーンアップ
        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("初期状態のaudioLevelは0.0")
    func initialAudioLevel() async {
        let sm = await createSessionManager()
        let level = await sm.audioLevel
        #expect(level == 0.0)
    }

    @Test("セッション終了後にaudioLevelが0.0にリセットされる")
    func audioLevelResetAfterSession() async throws {
        let mockAudio = MockAudioCaptureService()
        mockAudio.currentAudioLevel = 0.5
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .textChanged(partial: "テスト")),
            RecognitionEvent(kind: .lineCompleted(final: "テスト"))
        ]
        let sm = await createSessionManager(audioService: mockAudio, speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        let level = await sm.audioLevel
        #expect(level == 0.0)
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
