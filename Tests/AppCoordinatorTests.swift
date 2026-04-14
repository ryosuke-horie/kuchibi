import Combine
import Foundation
import Testing
@testable import Kuchibi

/// `AppCoordinator` 全体の統合テストは macOS のメニューバー／通知センター依存のため困難。
/// 代替として、AppCoordinator が担う主要配線ロジック（`EngineSwitchCoordinator`）を
/// 単独で検証する。Combine / MainActor / deferred apply の挙動を最小限カバーする。
@Suite("AppCoordinator (EngineSwitchCoordinator)", .serialized)
@MainActor
struct AppCoordinatorTests {
    /// `EngineSwitching` のテスト用スパイ。
    final class SpySwitcher: EngineSwitching {
        private(set) var calls: [(engine: SpeechEngine, language: String)] = []
        var shouldThrow: Bool = false

        func switchEngine(to engine: SpeechEngine, language: String) async throws {
            calls.append((engine: engine, language: language))
            if shouldThrow {
                throw KuchibiError.modelLoadFailed(
                    underlying: NSError(domain: "test", code: -1)
                )
            }
        }
    }

    private func makeCoordinator(
        initialState: SessionState = .idle,
        engineSubject: CurrentValueSubject<SpeechEngine, Never> = .init(.whisperKit(.base))
    ) -> (EngineSwitchCoordinator, MockSessionManager, SpySwitcher, CurrentValueSubject<SpeechEngine, Never>) {
        let session = MockSessionManager(initialState: initialState)
        let switcher = SpySwitcher()
        let coord = EngineSwitchCoordinator(
            engineRequestPublisher: engineSubject.dropFirst().eraseToAnyPublisher(),
            sessionStatePublisher: session.statePublisher,
            sessionStateProvider: { [weak session] in session?.state ?? .idle },
            switcher: switcher,
            language: "ja"
        )
        coord.start()
        return (coord, session, switcher, engineSubject)
    }

    // MARK: - idle 時の即時適用

    @Test("idle の状態でエンジン要求が来たら即座に switchEngine が 1 回呼ばれる")
    func appliesImmediatelyWhenIdle() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (coord, _, switcher, _) = makeCoordinator(initialState: .idle, engineSubject: subject)

        subject.send(.whisperKit(.largeV3Turbo))

        // Task で switchEngine が非同期に呼ばれるので待機
        try await Task.sleep(for: .milliseconds(50))

        #expect(coord.appliedCount == 1)
        #expect(coord.lastAppliedEngine == .whisperKit(.largeV3Turbo))
        #expect(switcher.calls.count == 1)
        #expect(switcher.calls.first?.engine == .whisperKit(.largeV3Turbo))
        #expect(switcher.calls.first?.language == "ja")
    }

    // MARK: - recording 中の保留

    @Test("recording 中のエンジン要求は保留され、idle 遷移で 1 回だけ適用される")
    func deferredApplyOnIdleTransition() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (coord, session, switcher, _) = makeCoordinator(
            initialState: .recording,
            engineSubject: subject
        )

        // recording 中にエンジン切替要求
        subject.send(.whisperKit(.largeV3Turbo))
        try await Task.sleep(for: .milliseconds(30))

        // まだ呼ばれていない
        #expect(switcher.calls.isEmpty)
        #expect(coord.pendingEngineRequest == .whisperKit(.largeV3Turbo))

        // processing を挟んでから idle へ
        session.setState(.processing)
        try await Task.sleep(for: .milliseconds(10))
        #expect(switcher.calls.isEmpty)

        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(50))

        // idle 遷移で 1 回だけ呼ばれる
        #expect(switcher.calls.count == 1)
        #expect(switcher.calls.first?.engine == .whisperKit(.largeV3Turbo))
        #expect(coord.pendingEngineRequest == nil)
    }

    // MARK: - 多重 idle 通知に対する冪等性

    @Test("idle のまま複数回 state 通知が来ても switchEngine は 1 回しか呼ばれない")
    func idempotentAcrossRepeatedIdle() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (coord, session, switcher, _) = makeCoordinator(
            initialState: .recording,
            engineSubject: subject
        )

        subject.send(.whisperKit(.largeV3Turbo))
        try await Task.sleep(for: .milliseconds(10))
        #expect(switcher.calls.isEmpty)
        #expect(coord.pendingEngineRequest == .whisperKit(.largeV3Turbo))

        // recording → idle → recording → idle と遷移しても、pending は最初の idle で消費される
        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(100))

        session.setState(.recording)
        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(100))

        #expect(coord.appliedCount == 1)
        #expect(switcher.calls.count == 1)
    }

    // MARK: - 複数回の要求は最新のみが適用される

    @Test("recording 中に複数回エンジン要求が来た場合、最新の要求のみが idle 時に適用される")
    func latestRequestWins() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (coord, session, switcher, _) = makeCoordinator(
            initialState: .recording,
            engineSubject: subject
        )

        subject.send(.whisperKit(.largeV3Turbo))
        subject.send(.whisperKit(.base))
        subject.send(.whisperKit(.largeV3Turbo))
        try await Task.sleep(for: .milliseconds(10))

        // pending は最新値になっている
        #expect(coord.pendingEngineRequest == .whisperKit(.largeV3Turbo))

        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(100))

        #expect(coord.appliedCount == 1)
        #expect(switcher.calls.count == 1)
        #expect(switcher.calls.first?.engine == .whisperKit(.largeV3Turbo))
    }

    // MARK: - pending 無しでの idle 通知は no-op

    @Test("pending が無いときの idle 通知は switchEngine を呼ばない")
    func noOpWithoutPending() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (_, session, switcher, _) = makeCoordinator(
            initialState: .recording,
            engineSubject: subject
        )

        session.setState(.idle)
        try await Task.sleep(for: .milliseconds(30))

        #expect(switcher.calls.isEmpty)
    }

    // MARK: - switchEngine throw は握り潰される

    @Test("switchEngine が throw しても pipeline は黙ってログだけ出して継続する")
    func switchEngineThrowIsSwallowed() async throws {
        let subject = CurrentValueSubject<SpeechEngine, Never>(.whisperKit(.base))
        let (coord, _, switcher, _) = makeCoordinator(initialState: .idle, engineSubject: subject)
        switcher.shouldThrow = true

        subject.send(.whisperKit(.largeV3Turbo))
        try await Task.sleep(for: .milliseconds(100))

        // tryApplyPending は 1 回呼ばれ pending がクリアされる
        #expect(coord.appliedCount == 1)
        #expect(coord.pendingEngineRequest == nil)
        // 呼び出し自体は 1 回行われる
        #expect(switcher.calls.count == 1)
    }
}
