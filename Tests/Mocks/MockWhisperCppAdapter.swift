import AVFoundation
@testable import Kuchibi

/// `WhisperCppAdapter` の代替として使えるテスト用モック。
///
/// `SpeechRecognitionAdapting` 準拠で、`MockSpeechRecognitionAdapter` と同様の役割を担うが、
/// `WhisperCppAdapter` 固有の挙動（`.kotobaWhisperBilingual` 専用 / モデル未配置時の throw）を
/// 模擬したいテストで使えるよう個別に用意する。
final class MockWhisperCppAdapter: SpeechRecognitionAdapting {
    var isInitialized = false
    var initializedEngine: SpeechEngine?
    var initializedLanguage: String?
    var shouldThrowOnInit = false
    var initThrowError: KuchibiError?
    var shouldThrowOnStartStream = false
    var startStreamCalled = false
    var addedBuffers: [AVAudioPCMBuffer] = []
    var partialText = ""
    var finalText = ""
    var onTextChangedCallback: ((String) -> Void)?
    var onLineCompletedCallback: ((String) -> Void)?

    func initialize(engine: SpeechEngine, language: String) async throws {
        if shouldThrowOnInit {
            throw initThrowError
                ?? KuchibiError.modelLoadFailed(underlying: NSError(domain: "MockWhisperCppAdapter", code: 1))
        }
        guard case .kotobaWhisperBilingual = engine else {
            throw KuchibiError.engineMismatch(
                expected: .kotobaWhisperBilingual(.v1Q5),
                actual: engine
            )
        }
        initializedEngine = engine
        initializedLanguage = language
        isInitialized = true
    }

    func startStream(
        onTextChanged: @escaping (String) -> Void,
        onLineCompleted: @escaping (String) -> Void
    ) throws {
        if shouldThrowOnStartStream {
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(
                    domain: "MockWhisperCppAdapter",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]
                )
            )
        }
        onTextChangedCallback = onTextChanged
        onLineCompletedCallback = onLineCompleted
        startStreamCalled = true
    }

    func addAudio(_ buffer: AVAudioPCMBuffer) {
        addedBuffers.append(buffer)
    }

    func getPartialText() -> String {
        partialText
    }

    func finalize() async -> String {
        isInitialized = false
        return finalText
    }
}
