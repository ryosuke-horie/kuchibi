import AVFoundation

/// 音声認識エンジンの汎用アダプタープロトコル
protocol SpeechRecognitionAdapting {
    func initialize(modelName: String) async throws
    func startStream(onTextChanged: @escaping (String) -> Void, onLineCompleted: @escaping (String) -> Void) throws
    func addAudio(_ buffer: AVAudioPCMBuffer)
    func getPartialText() -> String
    func finalize() async -> String
}
