import AVFoundation
import os

/// マイク音声のリアルタイムキャプチャサービス
final class AudioCaptureServiceImpl: AudioCapturing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "AudioCapture")

    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var isCapturing: Bool = false
    private(set) var currentAudioLevel: Float = 0.0

    func startCapture(noiseSuppressionEnabled: Bool) throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isCapturing else {
            Self.logger.warning("startCapture が既にキャプチャ中に呼ばれたため無視します")
            return AsyncStream { _ in }
        }

        let newEngine = AVAudioEngine()

        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.continuation = continuation
        }

        let inputNode = newEngine.inputNode

        // Voice Processing の設定（エンジン起動前にのみ可能）
        // 失敗時はノイズ抑制なしで録音を継続する（BT ヘッドセット等では非対応の場合がある）
        if noiseSuppressionEnabled {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                Self.logger.info("Voice Processing を有効化")
            } catch {
                Self.logger.warning("Voice Processing の有効化に失敗（ノイズ抑制なしで続行）: \(error.localizedDescription)")
            }
        }

        // Voice Processing 有効化後にフォーマットを取得（フォーマットが変わる場合がある）
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.updateAudioLevel(from: buffer)
            self?.continuation?.yield(buffer)
        }

        do {
            try newEngine.start()
            engine = newEngine
            isCapturing = true
            Self.logger.info("音声キャプチャを開始")
        } catch {
            let nsError = error as NSError
            Self.logger.error("音声キャプチャの開始に失敗: domain=\(nsError.domain) code=\(nsError.code) \(error.localizedDescription)")
            newEngine.inputNode.removeTap(onBus: 0)
            continuation?.finish()
            continuation = nil
            throw KuchibiError.microphoneUnavailable
        }

        return stream
    }

    func stopCapture() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        isCapturing = false
        currentAudioLevel = 0.0
        Self.logger.info("音声キャプチャを停止、オーディオハードウェアを解放")
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
