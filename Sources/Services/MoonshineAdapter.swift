import AVFoundation
import MoonshineVoice
import os

/// Moonshine SPMライブラリのアダプター
/// Transcriber + Stream APIをラップし、音声データの入力とイベント取得を提供する
final class MoonshineAdapterImpl: MoonshineAdapting {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "MoonshineAdapter")

    private var transcriber: Transcriber?
    private var stream: MoonshineVoice.Stream?
    private var latestText: String = ""

    func initialize(modelName: String) async throws {
        do {
            // モデルファイルのパスを解決
            guard let modelPath = resolveModelPath(modelName: modelName) else {
                throw KuchibiError.modelLoadFailed(
                    underlying: NSError(
                        domain: "com.kuchibi.app",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "モデルファイルが見つかりません: \(modelName)"]
                    ))
            }

            transcriber = try Transcriber(
                modelPath: modelPath,
                modelArch: .tinyStreaming
            )
            Self.logger.info("Moonshineモデル '\(modelName)' を読み込み完了")
        } catch let error as KuchibiError {
            throw error
        } catch {
            Self.logger.error("Moonshineモデルの読み込みに失敗: \(error.localizedDescription)")
            throw KuchibiError.modelLoadFailed(underlying: error)
        }
    }

    func addAudio(_ buffer: AVAudioPCMBuffer) {
        guard let stream else {
            Self.logger.warning("音声データを破棄: ストリームが未初期化")
            return
        }

        // AVAudioPCMBufferから[Float]に変換
        guard let channelData = buffer.floatChannelData else {
            Self.logger.error("音声データを破棄: floatChannelDataがnil (format: \(buffer.format))")
            return
        }
        let frameLength = Int(buffer.frameLength)
        let floatData = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        let sampleRate = Int32(buffer.format.sampleRate)

        do {
            try stream.addAudio(floatData, sampleRate: sampleRate)
        } catch {
            Self.logger.error("音声データの追加に失敗: \(error.localizedDescription)")
        }
    }

    func getPartialText() -> String {
        latestText
    }

    func finalize() async -> String {
        guard let stream else {
            Self.logger.warning("finalize()がストリームなしで呼ばれた")
            return ""
        }

        do {
            try stream.stop()
            let transcript = try stream.updateTranscription(flags: TranscribeStreamFlags.flagForceUpdate)
            let text = transcript.lines.map(\.text).joined(separator: " ")
            self.stream = nil
            return text.isEmpty ? latestText : text
        } catch {
            Self.logger.error("ストリーム終了に失敗: \(error.localizedDescription)")
            self.stream = nil
            return ""
        }
    }

    /// ストリーミングセッションを開始する（SpeechRecognitionServiceから呼ばれる）
    func startStream(onTextChanged: @escaping (String) -> Void, onLineCompleted: @escaping (String) -> Void) throws {
        guard let transcriber else {
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(domain: "com.kuchibi.app", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]))
        }

        latestText = ""
        let newStream = try transcriber.createStream(updateInterval: 0.5)

        newStream.addListener { [weak self] event in
            if let textChanged = event as? LineTextChanged {
                self?.latestText = textChanged.line.text
                onTextChanged(textChanged.line.text)
            } else if let completed = event as? LineCompleted {
                onLineCompleted(completed.line.text)
            }
        }

        try newStream.start()
        self.stream = newStream
    }

    // MARK: - Private

    private func resolveModelPath(modelName: String) -> String? {
        // 1. アプリバンドル内のリソースを検索
        if let path = Bundle.main.resourcePath {
            let modelDir = (path as NSString).appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: modelDir) {
                return modelDir
            }
        }

        // 2. ホームディレクトリの .kuchibi/models/ を検索
        let homeModels = NSHomeDirectory() + "/.kuchibi/models/" + modelName
        if FileManager.default.fileExists(atPath: homeModels) {
            return homeModels
        }

        // 3. Moonshineフレームワークバンドルのリソースを検索
        if let frameworkBundle = Transcriber.frameworkBundle,
           let path = frameworkBundle.resourcePath {
            let modelDir = (path as NSString).appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: modelDir) {
                return modelDir
            }
        }

        return nil
    }
}
