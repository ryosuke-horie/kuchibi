import AVFoundation
import os

/// 音声ストリームからテキスト認識イベントを生成するサービス
final class SpeechRecognitionServiceImpl: SpeechRecognizing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SpeechRecognition")
    private let adapter: SpeechRecognitionAdapting
    private(set) var isModelLoaded: Bool = false

    init(adapter: SpeechRecognitionAdapting) {
        self.adapter = adapter
    }

    func loadModel(modelName: String) async throws {
        try await adapter.initialize(modelName: modelName)
        isModelLoaded = true
        Self.logger.info("音声認識モデルを読み込み完了")
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
