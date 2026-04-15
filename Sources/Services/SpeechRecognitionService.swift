import AVFoundation
import Combine
import os

/// 音声ストリームからテキスト認識イベントを生成するサービス（hot-swap 本実装）。
///
/// Task 5.1/5.2/5.3 で本格実装。
/// - adapter slot を 1 つ保持し、engine に応じた adapter を `adapterFactory` で生成する
/// - `loadInitialEngine(_:language:)` は init 直後のロード経路を提供
/// - `switchEngine(to:language:)` は旧 adapter の `finalize()` 完了を待ってから
///   新 adapter を `initialize` し、slot を差し替える
/// - precondition として `sessionStateProvider() == .idle` を要求し、違反時は
///   `KuchibiError.sessionActiveDuringSwitch` を throw する
/// - 新 adapter の `initialize` が失敗した場合は旧 engine に rollback し、
///   `lastSwitchError` にメッセージを書き込み、`NotificationService` で通知する
@MainActor
final class SpeechRecognitionServiceImpl: ObservableObject, SpeechRecognizing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SpeechRecognition")

    @Published private(set) var currentEngine: SpeechEngine
    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isSwitching: Bool = false
    @Published private(set) var lastSwitchError: String? = nil

    private let adapterFactory: (SpeechEngine) -> SpeechRecognitionAdapting
    private let appSettings: AppSettings?
    private let notificationService: NotificationServicing?
    private let sessionStateProvider: () -> SessionState

    private var adapter: SpeechRecognitionAdapting
    private var currentLanguage: String = "ja"

    /// Factory クロージャ DI 版のコンストラクタ（推奨）。
    /// `adapterFactory` で engine に応じた adapter を生成する。
    /// `sessionStateProvider` は `switchEngine` の precondition 判定に使う。
    init(
        adapterFactory: @escaping (SpeechEngine) -> SpeechRecognitionAdapting,
        initialEngine: SpeechEngine,
        appSettings: AppSettings? = nil,
        notificationService: NotificationServicing? = nil,
        sessionStateProvider: @escaping () -> SessionState = { .idle }
    ) {
        self.adapterFactory = adapterFactory
        self.appSettings = appSettings
        self.notificationService = notificationService
        self.sessionStateProvider = sessionStateProvider
        self.currentEngine = initialEngine
        self.adapter = adapterFactory(initialEngine)
    }

    /// 既存テスト互換用: 単一 adapter を注入する従来のコンストラクタ。
    /// 内部で `adapterFactory` を「常に渡された adapter を返す」クロージャに変換する。
    /// hot-swap テスト以外（単一 adapter のロード・ストリーム挙動のみ検証）で利用する。
    convenience init(
        adapter: SpeechRecognitionAdapting,
        initialEngine: SpeechEngine
    ) {
        self.init(
            adapterFactory: { _ in adapter },
            initialEngine: initialEngine,
            appSettings: nil,
            notificationService: nil,
            sessionStateProvider: { .idle }
        )
    }

    // MARK: - Engine Loading / Switching

    func loadInitialEngine(_ engine: SpeechEngine, language: String) async throws {
        try await adapter.initialize(engine: engine, language: language)
        currentEngine = engine
        currentLanguage = language
        isModelLoaded = true
        Self.logger.info("音声認識モデル '\(engine.modelIdentifier)' を言語 '\(language)' で読み込み完了")
    }

    func switchEngine(to engine: SpeechEngine, language: String) async throws {
        // Precondition: セッションが idle でない場合は切替不可
        guard sessionStateProvider() == .idle else {
            Self.logger.error("switchEngine 失敗: セッション状態が idle でない")
            throw KuchibiError.sessionActiveDuringSwitch
        }

        // 同一 engine の場合は no-op（`isSwitching` を立てない）
        if engine == currentEngine && isModelLoaded {
            Self.logger.info("switchEngine: 同一エンジン指定のため no-op (\(engine.modelIdentifier))")
            return
        }

        let previousEngine = currentEngine
        let previousAdapter = adapter
        let previousLanguage = currentLanguage

        isSwitching = true
        lastSwitchError = nil
        defer { isSwitching = false }

        // 旧 adapter を finalize
        _ = await previousAdapter.finalize()
        isModelLoaded = false

        // 新 adapter 生成・初期化
        let newAdapter = adapterFactory(engine)
        let newAdapterError: Error
        do {
            try await newAdapter.initialize(engine: engine, language: language)
            adapter = newAdapter
            currentEngine = engine
            currentLanguage = language
            isModelLoaded = true
            Self.logger.info("エンジンを '\(engine.modelIdentifier)' に切替完了")
            return
        } catch {
            newAdapterError = error
        }

        // ここに到達 = 新 adapter の initialize が失敗
        Self.logger.error("新エンジン '\(engine.modelIdentifier)' のロードに失敗: \(newAdapterError.localizedDescription)。旧エンジン '\(previousEngine.modelIdentifier)' に rollback")

        let wrappedError: KuchibiError = (newAdapterError as? KuchibiError) ?? .modelLoadFailed(underlying: newAdapterError)

        // Rollback: 旧エンジンへ戻す
        var rollbackSucceeded = false
        var rollbackErrorOpt: Error?
        do {
            try await previousAdapter.initialize(engine: previousEngine, language: previousLanguage)
            rollbackSucceeded = true
        } catch {
            rollbackErrorOpt = error
        }

        if rollbackSucceeded {
            adapter = previousAdapter
            currentEngine = previousEngine
            currentLanguage = previousLanguage
            isModelLoaded = true
            if let appSettings, appSettings.speechEngine != previousEngine {
                appSettings.speechEngine = previousEngine
            }
            let msg = (newAdapterError as? LocalizedError)?.errorDescription ?? "\(newAdapterError)"
            lastSwitchError = msg
            await notificationService?.sendErrorNotification(error: wrappedError)
            throw newAdapterError
        } else {
            // 再 initialize も失敗
            let rollbackError = rollbackErrorOpt ?? newAdapterError
            Self.logger.error("旧エンジン '\(previousEngine.modelIdentifier)' の再ロードにも失敗: \(rollbackError.localizedDescription)")
            // slot は古い adapter を保持（finalize 済みで機能的には使えないが一貫性保持）
            adapter = previousAdapter
            currentEngine = previousEngine
            currentLanguage = previousLanguage
            isModelLoaded = false
            if let appSettings, appSettings.speechEngine != previousEngine {
                appSettings.speechEngine = previousEngine
            }
            let msg = "エンジン切替失敗、旧エンジン復元も失敗: \(rollbackError.localizedDescription)"
            lastSwitchError = msg
            await notificationService?.sendErrorNotification(error: wrappedError)
            throw newAdapterError
        }
    }

    // MARK: - Audio Stream Processing

    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent> {
        let adapter = self.adapter

        return AsyncStream { continuation in
            Task {
                continuation.yield(RecognitionEvent(kind: .lineStarted))

                let lineCompletedEmitted = OSAllocatedUnfairLock(initialState: false)

                do {
                    try adapter.startStream(
                        onTextChanged: { partial in
                            continuation.yield(RecognitionEvent(kind: .textChanged(partial: partial)))
                        },
                        onLineCompleted: { final_ in
                            lineCompletedEmitted.withLock { $0 = true }
                            continuation.yield(RecognitionEvent(kind: .lineCompleted(final: final_)))
                        }
                    )
                } catch {
                    Self.logger.error("ストリーム開始に失敗: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }

                // 音声ストリームを消費してアダプターに送る
                for await buffer in stream {
                    adapter.addAudio(buffer)
                }

                // ストリーム終了 → lineCompletedがまだなら最終テキストを取得
                let finalText = await adapter.finalize()
                let wasEmitted = lineCompletedEmitted.withLock { $0 }
                if !wasEmitted && !finalText.isEmpty {
                    continuation.yield(RecognitionEvent(kind: .lineCompleted(final: finalText)))
                }
                continuation.finish()
            }
        }
    }
}
