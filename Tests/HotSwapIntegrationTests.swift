import AVFoundation
import Combine
import Foundation
import Testing
@testable import Kuchibi

/// Task 9.1: Hot-swap シナリオの統合テスト。
///
/// `SpeechRecognitionServiceImpl` + `EngineSwitchCoordinator` を組み合わせ、
/// `AppSettings.speechEngine` 変更 → セッション状態に応じた即時適用 / 保留 / rollback を検証する。
///
/// 既存の個別テスト（`SpeechRecognitionServiceTests`, `AppCoordinatorTests`）で
/// 単体の挙動は確認済みのため、本ファイルは cross-boundary な結合挙動にフォーカスする。
///
/// Requirements: 2.1, 2.2, 2.4
@Suite("HotSwap 統合テスト", .serialized)
@MainActor
struct HotSwapIntegrationTests {
    // MARK: - Helpers

    /// 各 test に隔離された UserDefaults で AppSettings を生成する
    private func makeIsolatedSettings(initialEngine: SpeechEngine = .whisperKit(.base)) -> AppSettings {
        let defaults = UserDefaults(suiteName: "test.hotswap.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "test.hotswap.\(UUID().uuidString)")
        let settings = AppSettings(defaults: defaults)
        settings.speechEngine = initialEngine
        return settings
    }

    /// engine.kind に応じた Mock adapter を返す factory（bag に履歴を保持）。
    private final class AdapterBag {
        var adapters: [MockSpeechRecognitionAdapter] = []
        /// `engine.kind` ごとの「次回生成時に失敗させる」フラグ
        var shouldFailOn: Set<SpeechEngineKind> = []
    }

    private func makeFactory(bag: AdapterBag) -> (SpeechEngine) -> SpeechRecognitionAdapting {
        return { engine in
            let adapter = MockSpeechRecognitionAdapter()
            adapter.label = engine.modelIdentifier
            if bag.shouldFailOn.contains(engine.kind) {
                adapter.shouldThrowOnInitialize = true
            }
            bag.adapters.append(adapter)
            return adapter
        }
    }

    /// 実体の `SpeechRecognitionServiceImpl` と `EngineSwitchCoordinator` を組み立てる。
    /// `SessionStatePublishing` は `MockSessionManager` を使ってテストから状態遷移を駆動する。
    private func makeWiring(
        initialEngine: SpeechEngine,
        settings: AppSettings,
        initialSessionState: SessionState = .idle,
        bag: AdapterBag,
        notification: MockNotificationService
    ) -> (
        service: SpeechRecognitionServiceImpl,
        coordinator: EngineSwitchCoordinator,
        sessionMock: MockSessionManager
    ) {
        let sessionMock = MockSessionManager(initialState: initialSessionState)

        let service = SpeechRecognitionServiceImpl(
            adapterFactory: makeFactory(bag: bag),
            initialEngine: initialEngine,
            appSettings: settings,
            notificationService: notification,
            sessionStateProvider: { [weak sessionMock] in sessionMock?.state ?? .idle }
        )

        // 実アプリと同じ配線: AppSettings.$speechEngine を drop(初期値) → engineRequestPublisher
        let engineRequestPublisher = settings.$speechEngine
            .dropFirst()
            .eraseToAnyPublisher()

        let coordinator = EngineSwitchCoordinator(
            engineRequestPublisher: engineRequestPublisher,
            sessionStatePublisher: sessionMock.statePublisher,
            sessionStateProvider: { [weak sessionMock] in sessionMock?.state ?? .idle },
            switcher: service,
            language: "ja"
        )
        coordinator.start()

        return (service, coordinator, sessionMock)
    }

    // MARK: - シナリオ 1: idle での即時切替成功

    @Test("idle のとき AppSettings.speechEngine 変更が即座に SpeechRecognitionServiceImpl に伝搬する")
    func idleImmediateSwitchSuccess() async throws {
        let bag = AdapterBag()
        let notification = MockNotificationService()
        let settings = makeIsolatedSettings(initialEngine: .whisperKit(.base))

        let (service, coord, session) = makeWiring(
            initialEngine: .whisperKit(.base),
            settings: settings,
            initialSessionState: .idle,
            bag: bag,
            notification: notification
        )

        // 初期ロード
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(service.isModelLoaded)

        // idle のまま Kotoba に切替要求
        settings.speechEngine = .kotobaWhisperBilingual(.v1Q5)

        // Combine → Task → switchEngine の完了を待機
        try await Task.sleep(for: .milliseconds(100))

        // 状態遷移を検証
        #expect(service.currentEngine == .kotobaWhisperBilingual(.v1Q5))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)
        #expect(service.lastSwitchError == nil)
        #expect(coord.appliedCount == 1)
        #expect(coord.pendingEngineRequest == nil)
        // NotificationService にエラーが届いていないこと
        #expect(notification.sentErrors.isEmpty)
        // セッション状態は idle のまま
        #expect(session.state == .idle)
    }

    // MARK: - シナリオ 2: 録音中切替要求を idle 後に適用

    @Test("recording 中の AppSettings.speechEngine 変更は保留され、idle 遷移で 1 回だけ適用される")
    func recordingDeferredSwitchAppliesOnIdle() async throws {
        let bag = AdapterBag()
        let notification = MockNotificationService()
        let settings = makeIsolatedSettings(initialEngine: .whisperKit(.base))

        let (service, coord, session) = makeWiring(
            initialEngine: .whisperKit(.base),
            settings: settings,
            initialSessionState: .recording,
            bag: bag,
            notification: notification
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.currentEngine == .whisperKit(.base))

        // recording 中に切替要求
        settings.speechEngine = .kotobaWhisperBilingual(.v1Q5)
        try await Task.sleep(for: .milliseconds(30))

        // まだ切替は発生していない
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(coord.pendingEngineRequest == .kotobaWhisperBilingual(.v1Q5))
        #expect(coord.appliedCount == 0)
        #expect(!service.isSwitching)

        // recording 中に switchEngine を直接呼ぶと Precondition throw されることを検証
        // （Mock Adapter が idle 以外で呼ばれたら throw する = sessionActiveDuringSwitch）
        do {
            try await service.switchEngine(to: .kotobaWhisperBilingual(.v1Q5), language: "ja")
            Issue.record("Expected sessionActiveDuringSwitch to throw while recording")
        } catch let error as KuchibiError {
            if case .sessionActiveDuringSwitch = error {
                // OK
            } else {
                Issue.record("Expected .sessionActiveDuringSwitch, got \(error)")
            }
        }
        // precondition throw 後も currentEngine は旧のまま
        #expect(service.currentEngine == .whisperKit(.base))

        // processing へ遷移しても pending はまだ適用されない
        session.setState(.processing)
        try await Task.sleep(for: .milliseconds(30))
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(coord.appliedCount == 0)

        // idle に遷移 → pending が 1 回だけ適用される
        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(150))

        #expect(service.currentEngine == .kotobaWhisperBilingual(.v1Q5))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)
        #expect(service.lastSwitchError == nil)
        #expect(coord.appliedCount == 1)
        #expect(coord.pendingEngineRequest == nil)
        #expect(notification.sentErrors.isEmpty)
    }

    // MARK: - シナリオ 3: 新 adapter initialize 失敗時に旧エンジンへ rollback

    @Test("新 adapter initialize 失敗時に currentEngine / AppSettings が旧エンジンへ rollback され、lastSwitchError にメッセージが入る")
    func rollbackOnNewAdapterInitializeFailure() async throws {
        let bag = AdapterBag()
        let notification = MockNotificationService()
        let settings = makeIsolatedSettings(initialEngine: .whisperKit(.base))

        let (service, coord, _) = makeWiring(
            initialEngine: .whisperKit(.base),
            settings: settings,
            initialSessionState: .idle,
            bag: bag,
            notification: notification
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.currentEngine == .whisperKit(.base))
        let initialInitCount = bag.adapters.first?.initializeCallCount ?? 0

        // 次回の Kotoba 生成では adapter を failing に設定
        bag.shouldFailOn.insert(.kotobaWhisperBilingual)

        // idle のまま Kotoba へ切替 → 失敗 → rollback
        settings.speechEngine = .kotobaWhisperBilingual(.v1Q5)

        // coordinator が Task で switchEngine を呼ぶ → 内部で throw が握り潰される
        // （EngineSwitchCoordinator 側は error を握り潰すが、SpeechRecognitionServiceImpl
        //   内で rollback が行われ、lastSwitchError と NotificationService への通知が発生する）
        try await Task.sleep(for: .milliseconds(200))

        // currentEngine は旧 WhisperKit に rollback されている
        #expect(service.currentEngine == .whisperKit(.base))
        #expect(service.isModelLoaded, "rollback 成功なので isModelLoaded は true")
        #expect(!service.isSwitching)
        // lastSwitchError に値が入っている
        #expect(service.lastSwitchError != nil)
        #expect(!(service.lastSwitchError?.isEmpty ?? true))
        // AppSettings も rollback される
        #expect(settings.speechEngine == .whisperKit(.base))
        // NotificationService にエラー通知が届いている
        #expect(!notification.sentErrors.isEmpty)
        let hasModelLoadFailed = notification.sentErrors.contains { err in
            if case .modelLoadFailed = err { return true }
            return false
        }
        #expect(hasModelLoadFailed)
        // coordinator は最低 1 回適用を試みた（rollback 時に AppSettings.speechEngine が
        // 旧エンジンへ書き戻されるため、Combine 経由でさらに 1 回 no-op 適用が走る可能性がある）
        #expect(coord.appliedCount >= 1)
        // rollback 時に旧 adapter が再 initialize されている
        let firstAdapter = bag.adapters.first
        #expect((firstAdapter?.initializeCallCount ?? 0) == initialInitCount + 1)
    }

    // MARK: - Mock Adapter の precondition 契約

    @Test("Mock Adapter の precondition: session != idle の状態で switchEngine を直接呼ぶと sessionActiveDuringSwitch が throw される")
    func mockAdapterThrowsWhenNotIdle() async throws {
        let bag = AdapterBag()
        let notification = MockNotificationService()
        let settings = makeIsolatedSettings(initialEngine: .whisperKit(.base))

        let (service, _, session) = makeWiring(
            initialEngine: .whisperKit(.base),
            settings: settings,
            initialSessionState: .idle,
            bag: bag,
            notification: notification
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")

        for nonIdle in [SessionState.recording, .processing] {
            session.setState(nonIdle)
            do {
                try await service.switchEngine(to: .whisperKit(.small), language: "ja")
                Issue.record("Expected sessionActiveDuringSwitch for state \(nonIdle)")
            } catch let error as KuchibiError {
                if case .sessionActiveDuringSwitch = error {
                    // OK
                } else {
                    Issue.record("Expected .sessionActiveDuringSwitch for \(nonIdle), got \(error)")
                }
            }
            // state を変えても currentEngine は不変
            #expect(service.currentEngine == .whisperKit(.base))
        }
    }
}
