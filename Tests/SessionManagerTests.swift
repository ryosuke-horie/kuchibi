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
        #expect(mockOutput.outputCalls.first?.mode == .autoInput)
    }

    @Test("AppSettingsのoutputModeがデフォルトでautoInput")
    @MainActor
    func defaultOutputMode() async {
        let defaults = UserDefaults(suiteName: "test.sessionmanager")!
        defaults.removePersistentDomain(forName: "test.sessionmanager")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.outputMode == .autoInput)
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
            RecognitionEvent(kind: .textChanged(partial: "途中テキスト"))
        ]
        let sm = await createSessionManager(speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        let partial = await sm.partialText
        #expect(partial == "途中テキスト")
    }

    @Test("lineCompleted後にpartialTextがリセットされる")
    func partialTextResetAfterLineCompleted() async throws {
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
        #expect(partial == "")
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

    // MARK: - モニタリング統合テスト

    @Test("モニタリング有効時にセッション開始・完了が通知される")
    @MainActor
    func monitoringEnabledNotifiesStartAndEnd() async throws {
        let mockMonitoring = MockSessionMonitoringService()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "テスト"))
        ]
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.monitoring.\(UUID().uuidString)")!)
        settings.monitoringEnabled = true

        let sm = createSessionManager(
            speechService: mockASR,
            appSettings: settings,
            monitoring: mockMonitoring
        )

        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))

        #expect(mockMonitoring.sessionStartedCalls == 1)
        #expect(mockMonitoring.textCompletedCalls == ["テスト"])
        #expect(mockMonitoring.sessionEndedCalls == 1)
    }

    @Test("モニタリング無効時にはモニタリングメソッドが呼ばれない")
    @MainActor
    func monitoringDisabledSkipsNotification() async throws {
        let mockMonitoring = MockSessionMonitoringService()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "テスト"))
        ]
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.monitoring.\(UUID().uuidString)")!)
        settings.monitoringEnabled = false

        let sm = createSessionManager(
            speechService: mockASR,
            appSettings: settings,
            monitoring: mockMonitoring
        )

        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))

        #expect(mockMonitoring.sessionStartedCalls == 0)
        #expect(mockMonitoring.textCompletedCalls.isEmpty)
        #expect(mockMonitoring.sessionEndedCalls == 0)
    }

    // MARK: - テキスト蓄積テスト

    @Test("lineCompleted発生時にOutputManagerが即座に呼ばれない")
    @MainActor
    func outputNotCalledDuringRecording() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.holdStream = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "テスト行"))
        ]
        let sm = createSessionManager(outputManager: mockOutput, speechService: mockASR)

        await sm.startSession()
        // イベントが処理されるのを待つが、ストリームはまだ終了しない
        try await Task.sleep(for: .milliseconds(100))

        // recording中はOutputManagerが呼ばれない
        #expect(mockOutput.outputCalls.isEmpty)

        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("複数のlineCompleted後にセッション終了で改行結合テキストが出力される")
    func multipleLineCompletedOutputsJoinedText() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "1行目")),
            RecognitionEvent(kind: .lineCompleted(final: "2行目")),
            RecognitionEvent(kind: .lineCompleted(final: "3行目"))
        ]
        let sm = await createSessionManager(outputManager: mockOutput, speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        #expect(mockOutput.outputCalls.count == 1)
        #expect(mockOutput.outputCalls.first?.text == "1行目\n2行目\n3行目")
    }

    @Test("lineCompletedが発生せずセッション終了した場合にOutputManagerが呼ばれない")
    func noOutputWhenNoLineCompleted() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = []
        let sm = await createSessionManager(outputManager: mockOutput, speechService: mockASR)

        await sm.startSession()
        await sm.stopSession()

        try await Task.sleep(for: .milliseconds(200))
        #expect(mockOutput.outputCalls.isEmpty)
    }

    @Test("後処理有効時に処理済みテキストがバッファに蓄積される")
    @MainActor
    func postprocessedTextAccumulated() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "テスト 文"))
        ]
        let mockPostprocessor = MockTextPostprocessor()
        mockPostprocessor.transformFunction = { text in
            text.replacingOccurrences(of: " ", with: "")
        }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.accumulate.\(UUID().uuidString)")!)
        settings.textPostprocessingEnabled = true

        let sm = createSessionManager(
            outputManager: mockOutput,
            speechService: mockASR,
            appSettings: settings,
            textPostprocessor: mockPostprocessor
        )

        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))

        #expect(mockPostprocessor.processCalls == ["テスト 文"])
        #expect(mockOutput.outputCalls.first?.text == "テスト文")
    }

    @Test("後処理無効時に元テキストがそのままバッファに蓄積される")
    @MainActor
    func rawTextAccumulatedWhenPostprocessingDisabled() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "テスト 文"))
        ]
        let mockPostprocessor = MockTextPostprocessor()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.accumulate.\(UUID().uuidString)")!)
        settings.textPostprocessingEnabled = false

        let sm = createSessionManager(
            outputManager: mockOutput,
            speechService: mockASR,
            appSettings: settings,
            textPostprocessor: mockPostprocessor
        )

        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))

        #expect(mockPostprocessor.processCalls.isEmpty)
        #expect(mockOutput.outputCalls.first?.text == "テスト 文")
    }

    @Test("セッション開始時にバッファが初期化される")
    func bufferInitializedOnSessionStart() async throws {
        let mockOutput = MockOutputManager()
        let mockASR = MockSpeechRecognitionService()
        mockASR.isModelLoaded = true
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "1回目"))
        ]
        let sm = await createSessionManager(outputManager: mockOutput, speechService: mockASR)

        // 1回目のセッション
        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))
        #expect(mockOutput.outputCalls.count == 1)
        #expect(mockOutput.outputCalls.first?.text == "1回目")

        // 2回目のセッション — バッファが初期化されているので1回目のテキストは含まれない
        mockASR.eventsToEmit = [
            RecognitionEvent(kind: .lineCompleted(final: "2回目"))
        ]
        await sm.startSession()
        await sm.stopSession()
        try await Task.sleep(for: .milliseconds(200))
        #expect(mockOutput.outputCalls.count == 2)
        #expect(mockOutput.outputCalls.last?.text == "2回目")
    }

    // MARK: - Helper

    @MainActor
    private func createSessionManager(
        audioService: AudioCapturing? = nil,
        outputManager: OutputManaging? = nil,
        speechService: SpeechRecognizing? = nil,
        notificationService: NotificationServicing? = nil,
        appSettings: AppSettings? = nil,
        textPostprocessor: TextPostprocessing? = nil,
        monitoring: SessionMonitoring? = nil
    ) -> SessionManagerImpl {
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
        let settings = appSettings ?? AppSettings(defaults: UserDefaults(suiteName: "test.sessionmanager.\(UUID().uuidString)")!)
        return SessionManagerImpl(
            audioService: audio,
            speechService: asr,
            outputManager: output,
            notificationService: notification,
            appSettings: settings,
            textPostprocessor: textPostprocessor ?? MockTextPostprocessor(),
            monitoring: monitoring ?? MockSessionMonitoringService()
        )
    }
}
