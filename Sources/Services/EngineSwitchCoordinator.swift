import Combine
import Foundation
import os

/// `SessionState` の Publisher を提供する抽象。
///
/// `AppCoordinator` が `SessionManagerImpl.$state` を購読するためのプロトコル境界。
/// テストでは Mock 実装を注入して、任意のタイミングで `.idle` 遷移を再現できる。
@MainActor
protocol SessionStatePublishing: AnyObject {
    /// 現在のセッション状態
    var state: SessionState { get }
    /// セッション状態の Publisher。状態変化のたびに発行する。
    var statePublisher: AnyPublisher<SessionState, Never> { get }
}

/// エンジン切替のみを要求する最小抽象（`SpeechRecognizing` のうち切替側のみ）。
///
/// 単独切替ロジックのテストを容易にするため、`switchEngine(to:language:)` のみを
/// 要求するプロトコルとして分離する。`SpeechRecognitionServiceImpl` は既にこの
/// シグネチャを提供しているため、extension で conform させるだけで良い。
@MainActor
protocol EngineSwitching: AnyObject {
    func switchEngine(to engine: SpeechEngine, language: String) async throws
}

extension SpeechRecognitionServiceImpl: EngineSwitching {}

extension SessionManagerImpl: SessionStatePublishing {
    var statePublisher: AnyPublisher<SessionState, Never> {
        $state.eraseToAnyPublisher()
    }
}

/// `AppSettings.$speechEngine` と `SessionStatePublishing.statePublisher` を合成し、
/// `state == .idle` の瞬間にのみ最新のエンジン要求を `EngineSwitching.switchEngine` に渡す配線責務。
///
/// AppCoordinator 本体からこの配線を取り出すことで、単体テスト可能にする。
/// 本クラス自体は切替ロジックを持たず、タイミング制御のみを担う。
@MainActor
final class EngineSwitchCoordinator {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "EngineSwitchCoordinator")

    private let engineRequestPublisher: AnyPublisher<SpeechEngine, Never>
    private let sessionStateProvider: () -> SessionState
    private let sessionStatePublisher: AnyPublisher<SessionState, Never>
    private let switcher: EngineSwitching
    private let modelAvailability: ModelAvailabilityChecking?
    private let language: String

    private var cancellables = Set<AnyCancellable>()
    private(set) var pendingEngineRequest: SpeechEngine?
    private(set) var appliedCount: Int = 0

    /// テスト用途として、`switchEngine` が呼ばれた回数を外部から観測するためのカウンタ。
    /// 本番用途では使用しない。
    private(set) var lastAppliedEngine: SpeechEngine?

    init(
        engineRequestPublisher: AnyPublisher<SpeechEngine, Never>,
        sessionStatePublisher: AnyPublisher<SessionState, Never>,
        sessionStateProvider: @escaping () -> SessionState,
        switcher: EngineSwitching,
        modelAvailability: ModelAvailabilityChecking? = nil,
        language: String = "ja"
    ) {
        self.engineRequestPublisher = engineRequestPublisher
        self.sessionStatePublisher = sessionStatePublisher
        self.sessionStateProvider = sessionStateProvider
        self.switcher = switcher
        self.modelAvailability = modelAvailability
        self.language = language
    }

    /// Combine の購読を開始する。`init` とは別に呼ぶことで、テスト時に
    /// 購読開始前に publisher を差し替えたり、AppCoordinator 側の構築順序を調整しやすくする。
    func start() {
        engineRequestPublisher
            .sink { [weak self] newEngine in
                guard let self else { return }
                self.pendingEngineRequest = newEngine
                Self.logger.debug("Engine change requested: \(newEngine.modelIdentifier, privacy: .public)")
                self.tryApplyPending()
            }
            .store(in: &cancellables)

        sessionStatePublisher
            .sink { [weak self] newState in
                guard let self else { return }
                // `@Published` は `willSet` タイミングで発行されるため、
                // このクロージャ内で `sessionStateProvider()` を参照すると古い値が返る。
                // そのため Publisher から渡された `newState` を優先して扱う。
                if newState == .idle {
                    self.tryApplyPending(currentStateOverride: .idle)
                }
            }
            .store(in: &cancellables)
    }

    /// 保留中のエンジン要求があり、かつ現在のセッション状態が `.idle` であれば、
    /// `switchEngine(to:language:)` を 1 回だけ呼び、`pendingEngineRequest` をクリアする。
    ///
    /// - Parameter currentStateOverride: `@Published` の `willSet` タイミングで発火された
    ///   Publisher 経由の呼び出しでは `sessionStateProvider()` が更新前の値を返すため、
    ///   Publisher から受け取った最新値を直接渡すためのオーバライド。
    ///   `nil` の場合は `sessionStateProvider()` を参照する。
    /// - Note: 本メソッドは同期的に保留判定と pending クリアを行い、
    ///   実際の `switchEngine` 呼び出しは `Task` で非同期に行う。
    ///   よって同一フレーム内で複数回呼ばれても、pending が 1 回だけ適用されることを保証する。
    func tryApplyPending(currentStateOverride: SessionState? = nil) {
        guard let engine = pendingEngineRequest else { return }
        let currentState = currentStateOverride ?? sessionStateProvider()
        guard currentState == .idle else { return }

        // モデル未配置時は switchEngine を呼ばず、AppSettings の選択状態を
        // 維持したまま pending をクリアする。SettingsView は AppSettings.speechEngine を
        // 参照して DL ガイドバナーを表示する。再試行はユーザーが「配置を確認」ボタンを
        // 押下することで `retryPending(with:)` 経由で行われる。
        if let availability = modelAvailability, !availability.isAvailable(for: engine) {
            pendingEngineRequest = nil
            Self.logger.info("switchEngine skipped: model not available for \(engine.modelIdentifier, privacy: .public)")
            return
        }

        pendingEngineRequest = nil
        appliedCount += 1
        lastAppliedEngine = engine
        let switcher = self.switcher
        let language = self.language
        Task {
            do {
                try await switcher.switchEngine(to: engine, language: language)
            } catch {
                // switchEngine 内部で NotificationService 経由の通知が行われているため、
                // ここでは握り潰す。ログのみ出す。
                Self.logger.error("switchEngine failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// モデルファイル配置後の再試行用エントリポイント。
    /// SettingsView の「配置を確認」ボタンから呼ばれることを想定し、
    /// 指定 engine を pending にセットして `tryApplyPending` を呼ぶ。
    func retryPending(with engine: SpeechEngine) {
        pendingEngineRequest = engine
        Self.logger.debug("Engine retry requested: \(engine.modelIdentifier, privacy: .public)")
        tryApplyPending()
    }
}
