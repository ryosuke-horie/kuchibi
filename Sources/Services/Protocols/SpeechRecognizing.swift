import AVFoundation

/// 音声認識サービスのプロトコル
protocol SpeechRecognizing {
    var isModelLoaded: Bool { get }

    func loadModel() async throws
    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent>
}
