import AVFoundation
@testable import Kuchibi

final class MockAudioCaptureService: AudioCapturing {
    var isCapturing: Bool = false
    var currentAudioLevel: Float = 0.0
    var micPermissionGranted: Bool = true
    var shouldThrowOnStart: Bool = false
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var stopCaptureCallCount: Int = 0

    var lastNoiseSuppressionEnabled: Bool?

    func startCapture(noiseSuppressionEnabled: Bool) throws -> AsyncStream<AVAudioPCMBuffer> {
        if shouldThrowOnStart {
            throw KuchibiError.microphoneUnavailable
        }
        lastNoiseSuppressionEnabled = noiseSuppressionEnabled
        isCapturing = true
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func stopCapture() {
        stopCaptureCallCount += 1
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
