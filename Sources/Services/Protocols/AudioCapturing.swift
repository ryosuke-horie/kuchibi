import AVFoundation

/// マイク音声キャプチャのプロトコル
protocol AudioCapturing {
    var isCapturing: Bool { get }

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer>
    func stopCapture()
    func requestMicrophonePermission() async -> Bool
}
