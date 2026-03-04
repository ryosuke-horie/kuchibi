import AVFoundation
@testable import Kuchibi

final class MockAudioPreprocessor: AudioPreprocessing {
    var lastVadEnabled: Bool?
    var lastVadThreshold: Float?

    func process(
        _ stream: AsyncStream<AVAudioPCMBuffer>,
        vadEnabled: Bool,
        vadThreshold: Float
    ) -> AsyncStream<AVAudioPCMBuffer> {
        lastVadEnabled = vadEnabled
        lastVadThreshold = vadThreshold
        // パススルー: 入力ストリームをそのまま返す
        return stream
    }
}
