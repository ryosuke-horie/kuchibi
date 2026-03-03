import AVFoundation
@testable import Kuchibi

final class MockAudioCaptureService: AudioCapturing {
    var isCapturing: Bool = false
    var micPermissionGranted: Bool = true
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func startCapture() -> AsyncStream<AVAudioPCMBuffer> {
        isCapturing = true
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func stopCapture() {
        isCapturing = false
        continuation?.finish()
        continuation = nil
    }

    func requestMicrophonePermission() async -> Bool {
        micPermissionGranted
    }

    func sendBuffer(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(buffer)
    }
}
