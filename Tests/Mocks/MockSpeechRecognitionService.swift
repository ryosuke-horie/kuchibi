import AVFoundation
import Combine
@testable import Kuchibi

final class MockSpeechRecognitionService: ObservableObject, SpeechRecognizing {
    @Published var currentEngine: SpeechEngine = .whisperKit(.base)
    @Published var isModelLoaded: Bool = false
    @Published var isSwitching: Bool = false
    @Published var lastSwitchError: String? = nil

    var loadedEngine: SpeechEngine?
    var loadedLanguage: String?
    var switchedEngines: [SpeechEngine] = []
    var shouldThrowOnLoad: Bool = false
    var shouldThrowOnSwitch: Bool = false
    var eventsToEmit: [RecognitionEvent] = []
    var holdStream: Bool = false
    private var streamContinuation: AsyncStream<RecognitionEvent>.Continuation?

    func loadInitialEngine(_ engine: SpeechEngine, language: String) async throws {
        if shouldThrowOnLoad {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        loadedEngine = engine
        loadedLanguage = language
        currentEngine = engine
        isModelLoaded = true
    }

    func switchEngine(to engine: SpeechEngine, language: String) async throws {
        if shouldThrowOnSwitch {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 2))
        }
        switchedEngines.append(engine)
        loadedLanguage = language
        currentEngine = engine
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
