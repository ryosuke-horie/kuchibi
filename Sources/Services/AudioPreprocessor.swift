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
                var converter: AVAudioConverter?
                var needsResampling: Bool?

                for await buffer in stream {
                    // リサンプリング判定（初回のみ）
                    if needsResampling == nil {
                        let inputFormat = buffer.format
                        let skip = inputFormat.sampleRate == Self.targetSampleRate
                            && inputFormat.channelCount == Self.targetChannelCount
                        needsResampling = !skip
                        if !skip {
                            converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)
                            if converter == nil {
                                Self.logger.warning("AVAudioConverter の初期化に失敗。リサンプリングをスキップ")
                                needsResampling = false
                            } else {
                                Self.logger.info("リサンプリング有効: \(inputFormat.sampleRate)Hz → \(Self.targetSampleRate)Hz")
                            }
                        } else {
                            Self.logger.info("入力が16kHzモノラルのためリサンプリングをスキップ")
                        }
                    }

                    // リサンプリング
                    let processedBuffer: AVAudioPCMBuffer
                    if needsResampling == true, let converter {
                        guard let resampled = resample(buffer: buffer, converter: converter) else {
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

    private func resample(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            Self.logger.error("出力バッファの作成に失敗")
            return nil
        }

        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            Self.logger.error("リサンプリングに失敗")
            return nil
        }

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
