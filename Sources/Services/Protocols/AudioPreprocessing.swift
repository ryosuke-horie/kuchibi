import AVFoundation

/// 音声前処理のプロトコル（リサンプリング、VAD）
protocol AudioPreprocessing {
    func process(
        _ stream: AsyncStream<AVAudioPCMBuffer>,
        vadEnabled: Bool,
        vadThreshold: Float
    ) -> AsyncStream<AVAudioPCMBuffer>
}
