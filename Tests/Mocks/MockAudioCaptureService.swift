import AVFoundation
@testable import Kuchibi

final class MockAudioCaptureService: AudioCapturing {
    var isCapturing: Bool = false
    var micPermissionGranted: Bool = true
    var shouldThrowOnStart: Bool = false
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        if shouldThrowOnStart {
            throw KuchibiError.microphoneUnavailable
        }
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
