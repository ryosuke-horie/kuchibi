import AVFoundation
import Testing
@testable import Kuchibi

@Suite("AudioPreprocessor")
struct AudioPreprocessorTests {
    // MARK: - Helper

    private static let format16kHz = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    private static let format48kHz = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 1,
        interleaved: false
    )!

    private func createBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount, amplitude: Float) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = amplitude
            }
        }
        return buffer
    }

    private func collectBuffers(from stream: AsyncStream<AVAudioPCMBuffer>) async -> [AVAudioPCMBuffer] {
        var buffers: [AVAudioPCMBuffer] = []
        for await buffer in stream {
            buffers.append(buffer)
        }
        return buffers
    }

    // MARK: - リサンプリングテスト

    @Test("48kHzの入力が16kHzにリサンプリングされる")
    func resamplesFrom48kTo16k() async {
        let preprocessor = AudioPreprocessorImpl()
        let inputBuffer = createBuffer(format: Self.format48kHz, frameCount: 4800, amplitude: 0.5)

        let inputStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.yield(inputBuffer)
            continuation.finish()
        }

        let outputStream = preprocessor.process(inputStream, vadEnabled: false, vadThreshold: 0.01)
        let outputs = await collectBuffers(from: outputStream)

        #expect(!outputs.isEmpty)
        for output in outputs {
            #expect(output.format.sampleRate == 16000)
            #expect(output.format.channelCount == 1)
        }
    }

    @Test("16kHz入力ではリサンプリングがスキップされる")
    func skipsResamplingFor16kHz() async {
        let preprocessor = AudioPreprocessorImpl()
        let inputBuffer = createBuffer(format: Self.format16kHz, frameCount: 1600, amplitude: 0.5)

        let inputStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.yield(inputBuffer)
            continuation.finish()
        }

        let outputStream = preprocessor.process(inputStream, vadEnabled: false, vadThreshold: 0.01)
        let outputs = await collectBuffers(from: outputStream)

        #expect(outputs.count == 1)
        // 同じバッファがそのまま通過する
        #expect(outputs[0].format.sampleRate == 16000)
        #expect(outputs[0].frameLength == 1600)
    }

    // MARK: - VAD テスト

    @Test("閾値以上のエネルギーを持つバッファが通過する")
    func vadPassesLoudBuffers() async {
        let preprocessor = AudioPreprocessorImpl()
        let loudBuffer = createBuffer(format: Self.format16kHz, frameCount: 1600, amplitude: 0.5)

        let inputStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.yield(loudBuffer)
            continuation.finish()
        }

        let outputStream = preprocessor.process(inputStream, vadEnabled: true, vadThreshold: 0.01)
        let outputs = await collectBuffers(from: outputStream)

        #expect(outputs.count == 1)
    }

    @Test("閾値以下のバッファがフィルタリングされる")
    func vadFiltersSilentBuffers() async {
        let preprocessor = AudioPreprocessorImpl()
        // amplitude 0.0 = 完全無音
        let silentBuffer = createBuffer(format: Self.format16kHz, frameCount: 1600, amplitude: 0.0)

        let inputStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.yield(silentBuffer)
            continuation.finish()
        }

        let outputStream = preprocessor.process(inputStream, vadEnabled: true, vadThreshold: 0.01)
        let outputs = await collectBuffers(from: outputStream)

        #expect(outputs.isEmpty)
    }

    @Test("VAD無効時は全バッファが通過する")
    func vadDisabledPassesAllBuffers() async {
        let preprocessor = AudioPreprocessorImpl()
        let silentBuffer = createBuffer(format: Self.format16kHz, frameCount: 1600, amplitude: 0.0)

        let inputStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.yield(silentBuffer)
            continuation.finish()
        }

        let outputStream = preprocessor.process(inputStream, vadEnabled: false, vadThreshold: 0.01)
        let outputs = await collectBuffers(from: outputStream)

        #expect(outputs.count == 1)
    }
}
