import AVFoundation
import Combine
import os

/// 音声ストリームからテキスト認識イベントを生成するサービス
///
/// Task 1.3 時点では hot-swap の最小スタブ実装。
/// - `loadInitialEngine`: adapter.initialize() をそのまま呼ぶ
/// - `switchEngine`: adapter.finalize() 後に adapter.initialize() を直列で呼ぶだけ
///   （旧 adapter finalize 待ち・rollback・SessionState 前提違反チェックは Task 5.1/5.2/5.3 で実装）
@MainActor
final class SpeechRecognitionServiceImpl: ObservableObject, SpeechRecognizing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SpeechRecognition")

    @Published private(set) var currentEngine: SpeechEngine
    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isSwitching: Bool = false
    @Published private(set) var lastSwitchError: String? = nil

    private var adapter: SpeechRecognitionAdapting

    init(adapter: SpeechRecognitionAdapting, initialEngine: SpeechEngine) {
        self.adapter = adapter
        self.currentEngine = initialEngine
    }

    func loadInitialEngine(_ engine: SpeechEngine, language: String) async throws {
        try await adapter.initialize(engine: engine, language: language)
        currentEngine = engine
        isModelLoaded = true
        Self.logger.info("音声認識モデル '\(engine.modelIdentifier)' を言語 '\(language)' で読み込み完了")
    }

    func switchEngine(to engine: SpeechEngine, language: String) async throws {
        // Task 1.3 の最小スタブ: 単純に旧 adapter を finalize してから同一 adapter を再 initialize する。
        // 本格的な hot-swap（新 adapter 生成、rollback、前提違反チェック）は Task 5.1/5.2/5.3 で実装。
        isSwitching = true
        defer { isSwitching = false }

        _ = await adapter.finalize()
        isModelLoaded = false

        try await adapter.initialize(engine: engine, language: language)
        currentEngine = engine
        isModelLoaded = true
        Self.logger.info("エンジンを '\(engine.modelIdentifier)' に切替（最小スタブ）")
    }

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
