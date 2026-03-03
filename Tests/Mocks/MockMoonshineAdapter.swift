import AVFoundation
@testable import Kuchibi

final class MockMoonshineAdapter: MoonshineAdapting {
    var isInitialized = false
    var shouldThrowOnInit = false
    var addedBuffers: [AVAudioPCMBuffer] = []
    var partialText = ""
    var finalText = ""

    func initialize(modelName: String) async throws {
        if shouldThrowOnInit {
            throw KuchibiError.modelLoadFailed(underlying: NSError(domain: "mock", code: 1))
        }
        isInitialized = true
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
