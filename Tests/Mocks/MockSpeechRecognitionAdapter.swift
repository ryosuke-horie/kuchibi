import AVFoundation
@testable import Kuchibi

final class MockSpeechRecognitionAdapter: SpeechRecognitionAdapting {
    var isInitialized = false
    var initializedModelName: String?
    var shouldThrowOnInit = false
    var shouldThrowOnStartStream = false
    var startStreamCalled = false
    var addedBuffers: [AVAudioPCMBuffer] = []
    var partialText = ""
    var finalText = ""

    func initialize(modelName: String) async throws {
        if shouldThrowOnInit {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        initializedModelName = modelName
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
        finalText
    }
}
