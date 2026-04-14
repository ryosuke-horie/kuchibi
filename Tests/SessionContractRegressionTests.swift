import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

/// Task 9.3: セッション契約不変性の回帰テスト。
///
/// `SessionManagerImpl` を実体として動かし、WhisperKit / Kotoba の両エンジン設定下で
/// 以下のセッション契約が変わらないことを cross-component に検証する。
///
/// - 状態機械: idle → recording → processing → idle の遷移
/// - TextPostprocessor がどちらのエンジンでも適用される
/// - OutputManager がどちらのエンジンでも設定された OutputMode で出力する
/// - ESC キャンセルでどちらのエンジンでも出力が抑止される
///
/// 個別の state machine / postprocessor / output の単体テストは
/// `SessionManagerTests` 等で済んでいるため、本ファイルは
/// **エンジン設定に依存せず同じ挙動になる**ことの cross-engine 回帰確認にフォーカスする。
///
/// Requirements: 4.1, 4.2, 4.3, 4.4
@Suite("SessionContract 不変性回帰テスト", .serialized)
@MainActor
struct SessionContractRegressionTests {
    // MARK: - Helpers

    /// 対象エンジン設定を currentEngine に持つ Mock SpeechRecognitionService を生成。
    /// 事前設定の `eventsToEmit` を用いてストリーム上で決定的に RecognitionEvent を発火する。
    private func makeMockASR(
        engine: SpeechEngine,
        events: [RecognitionEvent],
        holdStream: Bool = false
    ) -> MockSpeechRecognitionService {
        let mock = MockSpeechRecognitionService()
        mock.isModelLoaded = true
        mock.currentEngine = engine
        mock.eventsToEmit = events
        mock.holdStream = holdStream
        return mock
    }

    /// SessionManagerImpl を実体（TextPostprocessorImpl 実体）で組み立てる。
    /// `appSettings.speechEngine` はテスト呼び出し側で明示的に設定すること。
    private func makeSessionManager(
        mockASR: MockSpeechRecognitionService,
        outputManager: OutputManaging,
        settings: AppSettings,
        textPostprocessor: TextPostprocessing? = nil,
        accessibilityTrusted: @escaping () -> Bool = { true }
    ) -> SessionManagerImpl {
        return SessionManagerImpl(
            audioService: MockAudioCaptureService(),
            speechService: mockASR,
            outputManager: outputManager,
            notificationService: MockNotificationService(),
            appSettings: settings,
            textPostprocessor: textPostprocessor ?? TextPostprocessorImpl(),
            monitoring: MockSessionMonitoringService(),
            micAuthorizationStatus: { .authorized },
            accessibilityTrusted: accessibilityTrusted
        )
    }

    private func makeIsolatedSettings(
        engine: SpeechEngine,
        outputMode: OutputMode = .autoInput,
        textPostprocessingEnabled: Bool = true
    ) -> AppSettings {
        let defaults = UserDefaults(suiteName: "test.sessioncontract.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.speechEngine = engine
        settings.outputMode = outputMode
        settings.textPostprocessingEnabled = textPostprocessingEnabled
        return settings
    }

    /// 状態機械と出力契約を同時に検証するテスト本体。engine 設定のみ差し替える。
    ///
    /// セッション状態遷移を段階的に検証するため、`holdStream` は使わず通常の
    /// 自動終了ストリームを使い、`stopSession` で audio が切れると mock ASR が
    /// 自然に event を yield → finish することで idle まで到達させる。
    private func assertStateMachineAndOutput(
        engine: SpeechEngine,
        outputMode: OutputMode,
        expectedOutput: String
    ) async throws {
        let mockASR = makeMockASR(
            engine: engine,
            events: [RecognitionEvent(kind: .lineCompleted(final: expectedOutput))],
            holdStream: false
        )
        let output = MockOutputManager()
        let settings = makeIsolatedSettings(
            engine: engine,
            outputMode: outputMode,
            textPostprocessingEnabled: false
        )
        let sm = makeSessionManager(mockASR: mockASR, outputManager: output, settings: settings)

        // 1) 初期: idle
        #expect(sm.state == .idle)

        // 2) startSession → recording
        sm.startSession()
        #expect(sm.state == .recording)

        // 3) stopSession → processing (audio 終了で mock が events yield → continuation.finish)
        sm.stopSession()
        #expect(sm.state == .processing)

        // 4) event 配送と finishSession 完了を待機 → idle
        try await Task.sleep(for: .milliseconds(300))
        #expect(sm.state == .idle)

        // 5) 出力は期待値どおり、OutputMode も appSettings と一致
        #expect(output.outputCalls.count == 1)
        #expect(output.outputCalls.first?.text == expectedOutput)
        #expect(output.outputCalls.first?.mode == outputMode)
    }

    // MARK: - Requirement 4.1: 状態機械の維持

    @Test("状態機械: WhisperKit で idle → recording → processing → idle を遷移する")
    func stateMachineWhisperKit() async throws {
        try await assertStateMachineAndOutput(
            engine: .whisperKit(.base),
            outputMode: .autoInput,
            expectedOutput: "WhisperKitの結果"
        )
    }

    @Test("状態機械: Kotoba で idle → recording → processing → idle を遷移する")
    func stateMachineKotoba() async throws {
        try await assertStateMachineAndOutput(
            engine: .kotobaWhisperBilingual(.v1Q5),
            outputMode: .autoInput,
            expectedOutput: "Kotobaの結果"
        )
    }

    // MARK: - Requirement 4.2: TextPostprocessor の共通適用

    /// 後処理有効時、どちらのエンジン設定でも同じ後処理関数が適用されることを検証。
    @Test("TextPostprocessor: WhisperKit でも Kotoba でも同じ後処理が適用される")
    func textPostprocessorAppliedAcrossEngines() async throws {
        let raw = "テスト 文 です"
        let expectedProcessed = "テスト文です"

        for engine in [SpeechEngine.whisperKit(.base), .kotobaWhisperBilingual(.v1Q5)] {
            let mockASR = makeMockASR(
                engine: engine,
                events: [RecognitionEvent(kind: .lineCompleted(final: raw))]
            )
            let output = MockOutputManager()
            let postprocessor = MockTextPostprocessor()
            postprocessor.transformFunction = { text in
                text.replacingOccurrences(of: " ", with: "")
            }
            let settings = makeIsolatedSettings(engine: engine, textPostprocessingEnabled: true)
            let sm = makeSessionManager(
                mockASR: mockASR,
                outputManager: output,
                settings: settings,
                textPostprocessor: postprocessor
            )

            sm.startSession()
            sm.stopSession()
            try await Task.sleep(for: .milliseconds(200))

            #expect(
                postprocessor.processCalls == [raw],
                "engine=\(engine.modelIdentifier) で postprocessor が 1 回呼ばれるはず"
            )
            #expect(
                output.outputCalls.first?.text == expectedProcessed,
                "engine=\(engine.modelIdentifier) で後処理結果が OutputManager に渡されるはず"
            )
        }
    }

    // MARK: - Requirement 4.3: 出力モードの共通化

    /// clipboard / autoInput のどちらの OutputMode でも、engine に依らず同じモードで配送されることを検証。
    @Test("OutputMode: WhisperKit でも Kotoba でも clipboard モードが配送される")
    func outputModeClipboardAcrossEngines() async throws {
        for engine in [SpeechEngine.whisperKit(.base), .kotobaWhisperBilingual(.v1Q5)] {
            try await assertStateMachineAndOutput(
                engine: engine,
                outputMode: .clipboard,
                expectedOutput: "clipboard出力-\(engine.modelIdentifier)"
            )
        }
    }

    @Test("OutputMode: WhisperKit でも Kotoba でも autoInput モードが配送される")
    func outputModeAutoInputAcrossEngines() async throws {
        for engine in [SpeechEngine.whisperKit(.base), .kotobaWhisperBilingual(.v1Q5)] {
            try await assertStateMachineAndOutput(
                engine: engine,
                outputMode: .autoInput,
                expectedOutput: "autoInput出力-\(engine.modelIdentifier)"
            )
        }
    }

    // MARK: - Requirement 4.4: ESC キャンセル契約の維持

    /// ESC 由来の `cancelSession()` がどちらのエンジン設定でも
    /// 「蓄積テキスト破棄・出力抑止」契約を守ることを検証。
    @Test("ESC キャンセル: WhisperKit でも Kotoba でも出力が抑止される")
    func escapeCancelSuppressesOutputAcrossEngines() async throws {
        for engine in [SpeechEngine.whisperKit(.base), .kotobaWhisperBilingual(.v1Q5)] {
            let mockASR = makeMockASR(
                engine: engine,
                events: [RecognitionEvent(kind: .lineCompleted(final: "破棄されるべきテキスト"))],
                holdStream: true
            )
            let output = MockOutputManager()
            let settings = makeIsolatedSettings(engine: engine, textPostprocessingEnabled: false)
            let sm = makeSessionManager(mockASR: mockASR, outputManager: output, settings: settings)
            let mockEsc = MockEscapeKeyMonitor()

            mockEsc.startMonitoring {
                Task { @MainActor in
                    sm.cancelSession()
                }
            }

            sm.startSession()
            try await Task.sleep(for: .milliseconds(100))
            #expect(sm.state == .recording, "engine=\(engine.modelIdentifier) で recording に遷移するはず")

            // ESC キャンセル発火
            mockEsc.simulateEscapeKey()
            try await Task.sleep(for: .milliseconds(150))

            // 状態が idle に戻り、OutputManager は呼ばれていない
            #expect(sm.state == .idle, "engine=\(engine.modelIdentifier) で ESC 後 idle に戻るはず")
            #expect(
                output.outputCalls.isEmpty,
                "engine=\(engine.modelIdentifier) で ESC キャンセル後は出力されないはず"
            )
            // partialText も空
            #expect(sm.partialText == "")

            mockASR.finishStream()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("ESC キャンセル: partialText 中にキャンセルしても両エンジンで出力されない")
    func escapeCancelDuringPartialTextAcrossEngines() async throws {
        for engine in [SpeechEngine.whisperKit(.base), .kotobaWhisperBilingual(.v1Q5)] {
            let mockASR = makeMockASR(
                engine: engine,
                events: [
                    RecognitionEvent(kind: .textChanged(partial: "途中テキスト")),
                    RecognitionEvent(kind: .lineCompleted(final: "最終テキスト"))
                ],
                holdStream: true
            )
            let output = MockOutputManager()
            let settings = makeIsolatedSettings(engine: engine, textPostprocessingEnabled: false)
            let sm = makeSessionManager(mockASR: mockASR, outputManager: output, settings: settings)

            sm.startSession()
            try await Task.sleep(for: .milliseconds(100))
            sm.cancelSession()
            try await Task.sleep(for: .milliseconds(100))

            #expect(sm.state == .idle)
            #expect(output.outputCalls.isEmpty, "engine=\(engine.modelIdentifier) でキャンセル後に出力されないはず")
            #expect(sm.partialText == "")

            mockASR.finishStream()
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
