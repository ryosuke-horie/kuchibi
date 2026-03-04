import AVFoundation

/// マイク音声キャプチャのプロトコル
protocol AudioCapturing {
    var isCapturing: Bool { get }
    var currentAudioLevel: Float { get }

    func startCapture(noiseSuppressionEnabled: Bool) throws -> AsyncStream<AVAudioPCMBuffer>
    func stopCapture()
    func requestMicrophonePermission() async -> Bool
}

extension AudioCapturing {
    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        try startCapture(noiseSuppressionEnabled: false)
    }
}
