import AVFoundation
import WhisperKit
import os

/// WhisperKit ライブラリをラップし、SpeechRecognitionAdapting に準拠するアダプター
final class WhisperKitAdapter: SpeechRecognitionAdapting {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "WhisperKitAdapter")

    private var whisperKit: WhisperKit?
    private var currentLanguage: String = "ja"
    private let state = OSAllocatedUnfairLock(initialState: AdapterState())
    private var recognitionTask: Task<Void, Never>?
    private var onTextChanged: ((String) -> Void)?
    private var onLineCompleted: ((String) -> Void)?

    func initialize(engine: SpeechEngine, language: String) async throws {
        // WhisperKitAdapter は `.whisperKit` 系のみ受理する。
        // 他エンジンが渡された場合は `KuchibiError.engineMismatch` を投げてルーター側に判断を委ねる。
        guard case .whisperKit(let model) = engine else {
            Self.logger.error(
                "想定外のエンジンが渡されました: \(engine.modelIdentifier, privacy: .public)"
            )
            throw KuchibiError.engineMismatch(
                expected: .whisperKit(.base),
                actual: engine
            )
        }

        let modelName = model.rawValue
        currentLanguage = language

        do {
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
            Self.logger.info("WhisperKitモデル '\(modelName)' を言語 '\(language)' で読み込み完了")
        } catch {
            Self.logger.error("WhisperKitモデルの読み込みに失敗: \(error.localizedDescription)")
            throw KuchibiError.modelLoadFailed(underlying: error)
        }
    }

    func startStream(
        onTextChanged: @escaping (String) -> Void,
        onLineCompleted: @escaping (String) -> Void
    ) throws {
        guard whisperKit != nil else {
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(domain: "com.kuchibi.app", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]))
        }

        state.withLock { $0 = AdapterState() }
        self.onTextChanged = onTextChanged
        self.onLineCompleted = onLineCompleted

        // Task ベースの定期認識ループ（Timer の RunLoop 問題を回避）
        recognitionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { break }
                await self.performRecognition()
            }
        }
    }

    func addAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            Self.logger.error("音声データを破棄: floatChannelDataがnil")
            return
        }
        let frameLength = Int(buffer.frameLength)
        let floatData = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        state.withLock { $0.audioBuffer.append(contentsOf: floatData) }
    }

    func getPartialText() -> String {
        state.withLock { $0.latestText }
    }

    func finalize() async -> String {
        recognitionTask?.cancel()
        // 実行中の transcribe が完了するまで待機し、並行呼び出しを防ぐ
        await recognitionTask?.value
        recognitionTask = nil

        let currentState = state.withLock { s -> AdapterState in
            let copy = s
            s = AdapterState()
            return copy
        }

        // コールバックの nil 代入は行わない（performRecognition からの読み取りとのデータ競合を防止）
        // 次回の startStream で上書きされる。finalize 後のコールバック呼び出しは発生しない
        // （recognitionTask の完了を待機済みのため）

        guard let whisperKit, !currentState.audioBuffer.isEmpty else {
            return currentState.latestText
        }

        do {
            let options = DecodingOptions(language: currentLanguage)
            let results = try await whisperKit.transcribe(
                audioArray: currentState.audioBuffer,
                decodeOptions: options
            )
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? currentState.latestText : text
        } catch {
            Self.logger.error("最終認識に失敗: \(error.localizedDescription)")
            return currentState.latestText
        }
    }

    // MARK: - Private

    private struct AdapterState {
        var audioBuffer: [Float] = []
        var latestText: String = ""
        var isTranscribing: Bool = false
    }

    private func performRecognition() async {
        let canStart = state.withLock { s -> Bool in
            guard !s.isTranscribing, !s.audioBuffer.isEmpty else { return false }
            s.isTranscribing = true
            return true
        }
        guard canStart, let whisperKit else { return }

        defer { state.withLock { $0.isTranscribing = false } }

        let currentBuffer = state.withLock { $0.audioBuffer }

        do {
            let options = DecodingOptions(language: currentLanguage)
            let results = try await whisperKit.transcribe(
                audioArray: currentBuffer,
                decodeOptions: options
            )
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                state.withLock { $0.latestText = text }
                onTextChanged?(text)
            }
        } catch {
            Self.logger.error("定期認識に失敗: \(error.localizedDescription)")
        }
    }
}
