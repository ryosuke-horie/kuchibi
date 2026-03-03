import AVFoundation
import os

/// 音声ストリームからテキスト認識イベントを生成するサービス
final class SpeechRecognitionServiceImpl: SpeechRecognizing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SpeechRecognition")
    private static let defaultModelName = "moonshine-tiny-ja"

    private let adapter: MoonshineAdapting
    private(set) var isModelLoaded: Bool = false

    init(adapter: MoonshineAdapting) {
        self.adapter = adapter
    }

    func loadModel() async throws {
        try await adapter.initialize(modelName: Self.defaultModelName)
        isModelLoaded = true
        Self.logger.info("音声認識モデルを読み込み完了")
    }

    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent> {
        let adapter = self.adapter

        return AsyncStream { continuation in
            Task {
                continuation.yield(RecognitionEvent(kind: .lineStarted))

                // MoonshineAdapterImplの場合はストリーミングセッションを開始
                if let moonshineAdapter = adapter as? MoonshineAdapterImpl {
                    do {
                        try moonshineAdapter.startStream(
                            onTextChanged: { partial in
                                continuation.yield(RecognitionEvent(kind: .textChanged(partial: partial)))
                            },
                            onLineCompleted: { final_ in
                                continuation.yield(RecognitionEvent(kind: .lineCompleted(final: final_)))
                            }
                        )
                    } catch {
                        Self.logger.error("ストリーム開始に失敗: \(error.localizedDescription)")
                        continuation.yield(RecognitionEvent(kind: .lineCompleted(final: "")))
                        continuation.finish()
                        return
                    }
                }

                // 音声ストリームを消費してアダプターに送る
                for await buffer in stream {
                    adapter.addAudio(buffer)
                }

                // ストリーム終了 → 最終テキストを取得
                let finalText = await adapter.finalize()
                if !finalText.isEmpty {
                    continuation.yield(RecognitionEvent(kind: .lineCompleted(final: finalText)))
                }
                continuation.finish()
            }
        }
    }
}
