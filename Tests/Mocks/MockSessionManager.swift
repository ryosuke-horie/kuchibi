import Combine
@testable import Kuchibi

/// `SessionStatePublishing` のテスト用モック。
///
/// 任意のタイミングで `state` を外部から変更でき、`statePublisher` を購読している
/// Combine pipeline がその変更を受け取って動作するかを検証するのに使う。
@MainActor
final class MockSessionManager: SessionStatePublishing {
    @Published private(set) var state: SessionState

    var statePublisher: AnyPublisher<SessionState, Never> {
        $state.eraseToAnyPublisher()
    }

    init(initialState: SessionState = .idle) {
        self.state = initialState
    }

    /// テストから状態遷移を駆動するためのヘルパー。
    func setState(_ newState: SessionState) {
        state = newState
    }
}
