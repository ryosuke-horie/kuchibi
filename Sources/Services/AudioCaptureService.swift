import AVFoundation
import os

/// マイク音声のリアルタイムキャプチャサービス
final class AudioCaptureServiceImpl: AudioCapturing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "AudioCapture")

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isCapturing: Bool = false

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.continuation = continuation
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.continuation?.yield(buffer)
        }

        do {
            try engine.start()
            isCapturing = true
            Self.logger.info("音声キャプチャを開始")
        } catch {
            Self.logger.error("音声キャプチャの開始に失敗: \(error.localizedDescription)")
            engine.inputNode.removeTap(onBus: 0)
            continuation?.finish()
            throw KuchibiError.microphoneUnavailable
        }

        return stream
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isCapturing = false
        Self.logger.info("音声キャプチャを停止")
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
