import AVFoundation
@testable import Kuchibi

final class MockSpeechRecognitionService: SpeechRecognizing {
    var isModelLoaded: Bool = false
    var shouldThrowOnLoad: Bool = false
    var eventsToEmit: [RecognitionEvent] = []

    func loadModel() async throws {
        if shouldThrowOnLoad {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        isModelLoaded = true
    }

    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent> {
        let events = eventsToEmit
        return AsyncStream { continuation in
            Task {
                // 入力ストリームを消費
                for await _ in stream {}
                // 事前設定されたイベントを発行
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
