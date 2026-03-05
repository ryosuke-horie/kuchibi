import AVFoundation
@testable import Kuchibi

final class MockSpeechRecognitionService: SpeechRecognizing {
    var isModelLoaded: Bool = false
    var shouldThrowOnLoad: Bool = false
    var eventsToEmit: [RecognitionEvent] = []
    var holdStream: Bool = false
    private var streamContinuation: AsyncStream<RecognitionEvent>.Continuation?

    func loadModel(modelName: String) async throws {
        if shouldThrowOnLoad {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        isModelLoaded = true
    }

    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent> {
        let events = eventsToEmit
        let hold = holdStream
        return AsyncStream { continuation in
            if hold {
                self.streamContinuation = continuation
            }
            Task {
                // 入力ストリームを消費
                for await _ in stream {}
                // 事前設定されたイベントを発行
                for event in events {
                    continuation.yield(event)
                }
                if !hold {
                    continuation.finish()
                }
            }
        }
    }

    func yieldEvent(_ event: RecognitionEvent) {
        streamContinuation?.yield(event)
    }

    func finishStream() {
        streamContinuation?.finish()
        streamContinuation = nil
    }
}
