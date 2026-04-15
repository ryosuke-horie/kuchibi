import AVFoundation

/// 音声認識エンジンの汎用アダプタープロトコル
///
/// `initialize(engine:language:)` によりアダプター単位で 1 回初期化され、
/// 以降は `startStream` → `addAudio` → `finalize` のライフサイクルで利用される。
/// `finalize` 後は再度 `initialize` することで再利用可能。
protocol SpeechRecognitionAdapting {
    func initialize(engine: SpeechEngine, language: String) async throws
    func startStream(
        onTextChanged: @escaping (String) -> Void,
        onLineCompleted: @escaping (String) -> Void
    ) throws
    func addAudio(_ buffer: AVAudioPCMBuffer)
    func getPartialText() -> String
    func finalize() async -> String
}
