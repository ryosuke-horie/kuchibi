import AVFoundation

/// Moonshine ASRエンジンのアダプタープロトコル
protocol MoonshineAdapting {
    func initialize(modelName: String) async throws
    func addAudio(_ buffer: AVAudioPCMBuffer)
    func getPartialText() -> String
    func finalize() async -> String
}
