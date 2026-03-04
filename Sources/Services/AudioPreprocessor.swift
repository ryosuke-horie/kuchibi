import AVFoundation
import os

/// 音声バッファのリサンプリングとVADフィルタリングを実行する前処理サービス
final class AudioPreprocessorImpl: AudioPreprocessing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "AudioPreprocessing")
    private static let targetSampleRate: Double = 16000
    private static let targetChannelCount: AVAudioChannelCount = 1

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: targetChannelCount,
        interleaved: false
    )!

    func process(
        _ stream: AsyncStream<AVAudioPCMBuffer>,
        vadEnabled: Bool,
        vadThreshold: Float
    ) -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            Task {
                var needsResampling: Bool?
                var resamplingRatio: Double = 1.0

                for await buffer in stream {
                    // リサンプリング判定（初回のみ）
                    if needsResampling == nil {
                        let inputFormat = buffer.format
                        let skip = inputFormat.sampleRate == Self.targetSampleRate
                            && inputFormat.channelCount == Self.targetChannelCount
                        needsResampling = !skip
                        if !skip {
                            resamplingRatio = Self.targetSampleRate / inputFormat.sampleRate
                            Self.logger.info("リサンプリング有効: \(inputFormat.sampleRate)Hz → \(Self.targetSampleRate)Hz (ratio=\(resamplingRatio))")
                        } else {
                            Self.logger.info("入力が16kHzモノラルのためリサンプリングをスキップ")
                        }
                    }

                    // リサンプリング
                    let processedBuffer: AVAudioPCMBuffer
                    if needsResampling == true {
                        guard let resampled = resample(buffer: buffer, ratio: resamplingRatio) else {
                            continue
                        }
                        processedBuffer = resampled
                    } else {
                        processedBuffer = buffer
                    }

                    // VAD フィルタリング
                    if vadEnabled {
                        let rms = calculateRMS(buffer: processedBuffer)
                        if rms < vadThreshold {
                            continue
                        }
                    }

                    continuation.yield(processedBuffer)
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Private

    /// 線形補間によるリサンプリング
    private func resample(buffer: AVAudioPCMBuffer, ratio: Double) -> AVAudioPCMBuffer? {
        guard let channelData = buffer.floatChannelData else {
            Self.logger.error("リサンプリング失敗: floatChannelData が nil")
            return nil
        }

        let inputFrames = Int(buffer.frameLength)
        let outputFrames = Int(Double(inputFrames) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: AVAudioFrameCount(outputFrames)
        ) else {
            Self.logger.error("出力バッファの作成に失敗")
            return nil
        }

        guard let outputChannelData = outputBuffer.floatChannelData else {
            Self.logger.error("出力バッファの floatChannelData が nil")
            return nil
        }

        let inputSamples = channelData[0]
        let outputSamples = outputChannelData[0]
        let step = 1.0 / ratio  // 入力のステップ幅（例: 48kHz→16kHz では 3.0）

        for i in 0..<outputFrames {
            let srcPos = Double(i) * step
            let srcIndex = Int(srcPos)
            let fraction = Float(srcPos - Double(srcIndex))

            if srcIndex + 1 < inputFrames {
                // 線形補間
                outputSamples[i] = inputSamples[srcIndex] * (1.0 - fraction) + inputSamples[srcIndex + 1] * fraction
            } else if srcIndex < inputFrames {
                outputSamples[i] = inputSamples[srcIndex]
            } else {
                outputSamples[i] = 0.0
            }
        }

        outputBuffer.frameLength = AVAudioFrameCount(outputFrames)
        return outputBuffer
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0.0 }

        let samples = channelData[0]
        var sumOfSquares: Float = 0.0
        for i in 0..<frames {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        return sqrtf(sumOfSquares / Float(frames))
    }
}
