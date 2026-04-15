import AVFoundation
@testable import Kuchibi

final class MockSpeechRecognitionAdapter: SpeechRecognitionAdapting {
    var isInitialized = false
    var initializedEngine: SpeechEngine?
    var initializedLanguage: String?
    var shouldThrowOnInit = false
    /// Task 5.1/5.3: hot-swap テストで使用する別名。`shouldThrowOnInit` と同義。
    var shouldThrowOnInitialize: Bool {
        get { shouldThrowOnInit }
        set { shouldThrowOnInit = newValue }
    }
    var initializeCallCount = 0
    var finalizeCallCount = 0
    var shouldThrowOnStartStream = false
    var startStreamCalled = false
    var addedBuffers: [AVAudioPCMBuffer] = []
    var partialText = ""
    var finalText = ""

    /// 任意のラベル（factory で engine ごとに生成した Mock を識別するのに使う）
    var label: String = ""

    func initialize(engine: SpeechEngine, language: String) async throws {
        initializeCallCount += 1
        if shouldThrowOnInit {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        initializedEngine = engine
        initializedLanguage = language
        isInitialized = true
    }

    func startStream(onTextChanged: @escaping (String) -> Void, onLineCompleted: @escaping (String) -> Void) throws {
        if shouldThrowOnStartStream {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]))
        }
        startStreamCalled = true
    }

    func addAudio(_ buffer: AVAudioPCMBuffer) {
        addedBuffers.append(buffer)
    }

    func getPartialText() -> String {
        partialText
    }

    func finalize() async -> String {
        finalizeCallCount += 1
        return finalText
    }
}
