import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

@Suite("SpeechRecognitionService")
struct SpeechRecognitionServiceTests {
    @Test("loadInitialEngineでアダプターが初期化される")
    @MainActor
    func loadInitialEngine() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        #expect(!service.isModelLoaded)
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.isModelLoaded)
        #expect(mockAdapter.isInitialized)
        #expect(service.currentEngine == .whisperKit(.base))
    }

    @Test("loadInitialEngineで指定されたエンジンと言語がアダプターに渡される")
    @MainActor
    func loadInitialEnginePassesArguments() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        try await service.loadInitialEngine(.whisperKit(.largeV3Turbo), language: "en")
        #expect(mockAdapter.initializedEngine == .whisperKit(.largeV3Turbo))
        #expect(mockAdapter.initializedLanguage == "en")
    }

    @Test("loadInitialEngine失敗時にエラーをスローする")
    @MainActor
    func loadInitialEngineFailure() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.shouldThrowOnInit = true
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        do {
            try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is KuchibiError)
        }
    }

    @Test("switchEngineでcurrentEngineが更新される（単一アダプター経路）")
    @MainActor
    func switchEngineUpdatesCurrentEngine() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        try await service.switchEngine(to: .whisperKit(.small), language: "ja")

        #expect(service.currentEngine == .whisperKit(.small))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)
    }

    @Test("processAudioStreamがRecognitionEventを発行する")
    @MainActor
    func processAudioStream() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.partialText = "途中"
        mockAdapter.finalText = "完了テキスト"
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        // ストリームを作成してすぐ終了
        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.finish()
        }

        let eventStream = service.processAudioStream(audioStream)
        var events: [RecognitionEvent] = []
        for await event in eventStream {
            events.append(event)
        }

        // 少なくともlineCompletedが発行される
        let hasCompleted = events.contains { event in
            if case .lineCompleted = event.kind { return true }
            return false
        }
        #expect(hasCompleted)
    }

    // MARK: - Task 5.1: Adapter Factory による hot-swap

    @Test("switchEngine: WhisperKit → Kotoba → WhisperKit の連続切替が成立する")
    @MainActor
    func switchEngineSequentialFactory() async throws {
        // engine kind ごとに別 Mock を返す factory
        // factory の呼出履歴を記録するため box 経由で共有する
        final class AdapterBag {
            var adapters: [MockSpeechRecognitionAdapter] = []
        }
        let bag = AdapterBag()

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                let mock = MockSpeechRecognitionAdapter()
                mock.label = engine.modelIdentifier
                bag.adapters.append(mock)
                return mock
            },
            initialEngine: .whisperKit(.base)
        )

        // 初期ロード
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(service.isModelLoaded)

        // WhisperKit → Kotoba
        try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
        #expect(service.currentEngine == .kotobaWhisperBilingual(.v1Q5))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)

        // Kotoba → WhisperKit
        try await service.switchEngine(to: .whisperKit(.small), language: "ja")
        #expect(service.currentEngine == .whisperKit(.small))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)

        // factory が 3 つの adapter を生成していること（初期 + 2 回の切替）
        #expect(bag.adapters.count == 3)
        // 最初の adapter は finalize されている
        #expect(bag.adapters[0].finalizeCallCount >= 1)
        #expect(bag.adapters[1].finalizeCallCount >= 1)
    }

    @Test("switchEngine: 同一エンジン指定時は no-op で isSwitching が立たない")
    @MainActor
    func switchEngineSameEngineNoOp() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        var factoryCallCount = 0
        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { _ in
                factoryCallCount += 1
                return mockAdapter
            },
            initialEngine: .whisperKit(.base)
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        let initialInitCount = mockAdapter.initializeCallCount
        let initialFactoryCalls = factoryCallCount

        // 同一 engine で switchEngine
        try await service.switchEngine(to: .whisperKit(.base), language: "ja")

        // factory も initialize も再呼出されない
        #expect(factoryCallCount == initialFactoryCalls)
        #expect(mockAdapter.initializeCallCount == initialInitCount)
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(!service.isSwitching)
    }

    // MARK: - Task 5.2: precondition guard

    @Test("switchEngine: state != .idle のとき sessionActiveDuringSwitch が throw され currentEngine が不変")
    @MainActor
    func switchEnginePreconditionViolation() async throws {
        final class StateBox { var state: SessionState = .idle }
        let stateBox = StateBox()

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { _ in MockSpeechRecognitionAdapter() },
            initialEngine: .whisperKit(.base),
            sessionStateProvider: { stateBox.state }
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")

        // recording 中に切替要求
        stateBox.state = .recording
        do {
            try await service.switchEngine(to: .whisperKit(.small), language: "ja")
            Issue.record("Expected KuchibiError.sessionActiveDuringSwitch")
        } catch let error as KuchibiError {
            if case .sessionActiveDuringSwitch = error {
                // OK
            } else {
                Issue.record("Expected .sessionActiveDuringSwitch, got \(error)")
            }
        } catch {
            Issue.record("Expected KuchibiError, got \(error)")
        }

        // currentEngine は不変
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(!service.isSwitching)
        #expect(service.isModelLoaded)
    }

    // MARK: - Task 5.3: rollback + lastSwitchError + NotificationService

    @Test("switchEngine: 新 adapter initialize 失敗時に旧エンジンへ rollback される")
    @MainActor
    func switchEngineRollbackOnNewAdapterFailure() async throws {
        let initialAdapter = MockSpeechRecognitionAdapter()
        let failingAdapter = MockSpeechRecognitionAdapter()
        failingAdapter.shouldThrowOnInitialize = true

        var factoryCallCount = 0
        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                factoryCallCount += 1
                switch engine.kind {
                case .whisperKit:
                    return initialAdapter
                case .kotobaWhisperBilingual:
                    return failingAdapter
                }
            },
            initialEngine: .whisperKit(.base),
            notificationService: MockNotificationService()
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        let initAdapterInitializeCountBefore = initialAdapter.initializeCallCount

        // Kotoba への切替は失敗する
        do {
            try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
            Issue.record("Expected initialize failure to throw")
        } catch {
            #expect(error is KuchibiError)
        }

        // currentEngine は旧 WhisperKit のまま
        #expect(service.currentEngine == .whisperKit(.base))
        // 旧 adapter が rollback のため再 initialize されている
        #expect(initialAdapter.initializeCallCount == initAdapterInitializeCountBefore + 1)
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)
        // lastSwitchError に何か書かれている
        #expect(service.lastSwitchError != nil)
        #expect(!(service.lastSwitchError?.isEmpty ?? true))
    }

    @Test("switchEngine: 失敗時 AppSettings.speechEngine も元に戻される")
    @MainActor
    func switchEngineFailureRollsBackAppSettings() async throws {
        let appSettings = AppSettings()
        // 事前に WhisperKit 設定
        appSettings.speechEngine = .whisperKit(.base)

        let initialAdapter = MockSpeechRecognitionAdapter()
        let failingAdapter = MockSpeechRecognitionAdapter()
        failingAdapter.shouldThrowOnInitialize = true

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                switch engine.kind {
                case .whisperKit: return initialAdapter
                case .kotobaWhisperBilingual: return failingAdapter
                }
            },
            initialEngine: .whisperKit(.base),
            appSettings: appSettings,
            notificationService: MockNotificationService()
        )
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")

        // SettingsView から Kotoba に変更された想定で先に AppSettings を変える
        appSettings.speechEngine = .kotobaWhisperBilingual(.v1Q5)

        // 失敗する切替
        do {
            try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
            Issue.record("Expected failure")
        } catch {}

        // AppSettings も rollback されている
        #expect(appSettings.speechEngine == .whisperKit(.base))
    }

    @Test("switchEngine: 失敗時に NotificationService へエラー通知が届く")
    @MainActor
    func switchEngineFailureNotifiesUser() async throws {
        let initialAdapter = MockSpeechRecognitionAdapter()
        let failingAdapter = MockSpeechRecognitionAdapter()
        failingAdapter.shouldThrowOnInitialize = true
        let mockNotification = MockNotificationService()

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                switch engine.kind {
                case .whisperKit: return initialAdapter
                case .kotobaWhisperBilingual: return failingAdapter
                }
            },
            initialEngine: .whisperKit(.base),
            notificationService: mockNotification
        )
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")

        do {
            try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
            Issue.record("Expected failure")
        } catch {}

        // NotificationService に modelLoadFailed が届いている
        #expect(!mockNotification.sentErrors.isEmpty)
        let hasModelLoadFailed = mockNotification.sentErrors.contains { err in
            if case .modelLoadFailed = err { return true }
            return false
        }
        #expect(hasModelLoadFailed)
    }

    @Test("switchEngine: 新旧 adapter 両方 initialize が失敗すると isModelLoaded が false、lastSwitchError に値あり")
    @MainActor
    func switchEngineDoubleFailure() async throws {
        // 初期 adapter: loadInitial では成功、rollback 時の再 initialize で失敗するよう条件を切替
        let initialAdapter = MockSpeechRecognitionAdapter()
        let failingAdapter = MockSpeechRecognitionAdapter()
        failingAdapter.shouldThrowOnInitialize = true
        let mockNotification = MockNotificationService()

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                switch engine.kind {
                case .whisperKit: return initialAdapter
                case .kotobaWhisperBilingual: return failingAdapter
                }
            },
            initialEngine: .whisperKit(.base),
            notificationService: mockNotification
        )
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")

        // Rollback 時も失敗させるために loadInitial 後に初期 adapter の throw フラグを立てる
        initialAdapter.shouldThrowOnInitialize = true

        do {
            try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
            Issue.record("Expected failure")
        } catch {}

        // isModelLoaded = false、isSwitching = false
        #expect(!service.isModelLoaded)
        #expect(!service.isSwitching)
        // currentEngine は previousEngine (WhisperKit) のまま
        #expect(service.currentEngine == .whisperKit(.base))
        // lastSwitchError に「復元も失敗」メッセージ
        #expect(service.lastSwitchError != nil)
        // NotificationService にもエラー通知が届いている
        #expect(!mockNotification.sentErrors.isEmpty)
    }
}
