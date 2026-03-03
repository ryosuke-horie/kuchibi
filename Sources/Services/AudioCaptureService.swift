import AVFoundation
import os

/// マイク音声のリアルタイムキャプチャサービス
final class AudioCaptureServiceImpl: AudioCapturing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "AudioCapture")

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isCapturing: Bool = false
    private(set) var currentAudioLevel: Float = 0.0

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.continuation = continuation
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.updateAudioLevel(from: buffer)
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
        currentAudioLevel = 0.0
        Self.logger.info("音声キャプチャを停止")
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let samples = channelData[0]
        var sumOfSquares: Float = 0.0
        for i in 0..<frames {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(frames))
        currentAudioLevel = min(rms * 3.0, 1.0)
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
