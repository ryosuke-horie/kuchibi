import AVFoundation
import Foundation
import WhisperCppKit
import os

/// whisper.cpp (ggml) ライブラリをラップし、`SpeechRecognitionAdapting` に準拠するアダプター。
///
/// Kotoba-Whisper Bilingual GGML モデルを読み込んで擬似ストリーミング認識を行う。
///
/// ライフサイクル:
/// 1. `initialize(engine:language:)` で `whisper_init_from_file_with_params` により
///    コンテキストを生成し `OpaquePointer` として保持する。
/// 2. `startStream` で内部リングバッファをリセットし、定期的に確定処理を行う Task を起動する。
/// 3. `addAudio(_:)` で 16kHz mono Float32 サンプルを蓄積する。
/// 4. 30 秒（=480,000 samples @ 16kHz）窓に達するか、新規バッファ追加が一定時間 (`gapTimeout`)
///    無いまま蓄積バッファに音声が残っている場合に `whisper_full` を同期実行し、
///    確定テキストを `onLineCompleted` で通知してリングバッファをクリアする。
/// 5. `finalize()` で残バッファを処理して結果を返す。コンテキストは保持し次録音で再利用する
///    （連続録音のモデル再ロードを避けるため）。`whisper_free` は `deinit` または
///    再 `initialize` 時にのみ呼ばれる。
///
/// 並行安全性:
/// - `context` / `audioBuffer` / callbacks / `currentLanguage` はすべて `State` 構造体に集約し、
///   `OSAllocatedUnfairLock` 越しにのみアクセスする。これにより `Task.detached` 上で走る
///   `tickAndProcessIfReady` と、呼び出し元（MainActor 等）から呼ばれる
///   `initialize`/`finalize` の間の use-after-free や callback race を防止する。
/// - `whisper_full` は同期 C 関数で数百 ms〜数秒ブロックするため、ロックを解放した状態で呼ぶ
///   （`addAudio` が即応できるようにする）。ロック内ではコンテキスト・バッファ・コールバックの
///   スナップショットを取るだけにする。
/// - `processingTask` は `Task.detached` で協調スレッドプールに逃がし、MainActor をブロックしない
///   （UI の音量バーが固まる問題を回避）。
final class WhisperCppAdapter: SpeechRecognitionAdapting, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "WhisperCppAdapter")

    /// サンプリングレート（whisper.cpp は 16kHz mono Float32 を要求）
    private static let sampleRate = 16_000
    /// 30 秒窓 (= 480,000 samples @ 16kHz)
    private static let windowSamples = 30 * sampleRate
    /// 新規バッファが届かないまま確定処理に移るまでの猶予（VAD-lite gap detection）
    private static let gapTimeout: TimeInterval = 1.0
    /// `processingTask` の polling 周期
    private static let pollInterval: Duration = .milliseconds(200)
    /// `runWhisper` 前段のバッファ無音判定 RMS 閾値（これ未満なら whisper を呼ばず空文字を返す）
    private static let silenceRmsThreshold: Float = 0.003
    /// 連続 `whisper_full` 失敗回数の許容上限（超えたら上位へ通知して reset）
    private static let consecutiveFailureThreshold: Int = 3

    private let availability: ModelAvailabilityChecking
    private let notificationService: NotificationServicing?

    /// ロックで保護する全状態。ライフサイクルメソッドの並行呼び出しや
    /// `processingTask` と `initialize`/`finalize` の間の race を防ぐ。
    private struct State {
        var context: OpaquePointer?
        var language: String = "ja"
        var audioBuffer: [Float] = []
        var lastAppendedAt: Date?
        var onTextChanged: ((String) -> Void)?
        var onLineCompleted: ((String) -> Void)?
        var consecutiveFailureCount: Int = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var processingTask: Task<Void, Never>?

    init(
        availability: ModelAvailabilityChecking = ModelAvailabilityChecker(),
        notificationService: NotificationServicing? = nil
    ) {
        self.availability = availability
        self.notificationService = notificationService
    }

    deinit {
        let ctx = state.withLock { s -> OpaquePointer? in
            let c = s.context
            s.context = nil
            return c
        }
        if let ctx {
            whisper_free(ctx)
        }
    }

    // MARK: - SpeechRecognitionAdapting

    func initialize(engine: SpeechEngine, language: String) async throws {
        guard case .kotobaWhisperBilingual = engine else {
            Self.logger.error(
                "想定外のエンジンが渡されました: \(engine.modelIdentifier, privacy: .public)"
            )
            throw KuchibiError.engineMismatch(
                expected: .kotobaWhisperBilingual(.v1Q5),
                actual: engine
            )
        }

        // 既存コンテキストが残っていたら先に解放（重複 initialize 時のリーク防止）
        let existing = state.withLock { s -> OpaquePointer? in
            let c = s.context
            s.context = nil
            return c
        }
        if let existing {
            whisper_free(existing)
        }

        guard let path = availability.modelPath(for: engine) else {
            throw KuchibiError.modelFileMissing(path: "unknown")
        }
        guard FileManager.default.fileExists(atPath: path.path) else {
            Self.logger.error("Kotoba モデル未配置: \(path.path, privacy: .public)")
            throw KuchibiError.modelFileMissing(path: path.path)
        }

        let cparams = whisper_context_default_params()
        let ctx: OpaquePointer? = path.path.withCString { cPath in
            whisper_init_from_file_with_params(cPath, cparams)
        }
        guard let ctx else {
            Self.logger.error("whisper_init_from_file_with_params が nil を返しました")
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(
                    domain: "WhisperCppAdapter",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "whisper_init_from_file_with_params returned nil"]
                )
            )
        }

        state.withLock {
            $0.context = ctx
            $0.language = language
            $0.consecutiveFailureCount = 0
        }

        Self.logger.info(
            "whisper.cpp モデル '\(engine.modelIdentifier, privacy: .public)' を言語 '\(language, privacy: .public)' で読み込み完了"
        )
    }

    func startStream(
        onTextChanged: @escaping (String) -> Void,
        onLineCompleted: @escaping (String) -> Void
    ) throws {
        let hasContext = state.withLock { $0.context != nil }
        guard hasContext else {
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(
                    domain: "WhisperCppAdapter",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]
                )
            )
        }

        state.withLock {
            $0.audioBuffer.removeAll(keepingCapacity: false)
            $0.lastAppendedAt = nil
            $0.onTextChanged = onTextChanged
            $0.onLineCompleted = onLineCompleted
            $0.consecutiveFailureCount = 0
        }

        processingTask?.cancel()
        processingTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { break }
                self.tickAndProcessIfReady()
            }
        }
    }

    func addAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            Self.logger.error("音声データを破棄: floatChannelDataがnil")
            return
        }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let floatData = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        state.withLock {
            $0.audioBuffer.append(contentsOf: floatData)
            $0.lastAppendedAt = Date()
        }
    }

    func getPartialText() -> String {
        // 擬似ストリーミングでは部分テキストを公開しない
        ""
    }

    func finalize() async -> String {
        processingTask?.cancel()
        await processingTask?.value
        processingTask = nil

        let (leftover, ctx, language, onLineCompleted) = state.withLock {
            s -> ([Float], OpaquePointer?, String, ((String) -> Void)?) in
            let buf = s.audioBuffer
            s.audioBuffer.removeAll(keepingCapacity: false)
            let cb = s.onLineCompleted
            s.onTextChanged = nil
            s.onLineCompleted = nil
            return (buf, s.context, s.language, cb)
        }

        var finalText = ""
        if !leftover.isEmpty, let ctx {
            finalText = HallucinationFilter.filter(runWhisper(context: ctx, samples: leftover, language: language))
            if !finalText.isEmpty {
                onLineCompleted?(finalText)
            }
        }
        return finalText
    }

    // MARK: - Private

    private func tickAndProcessIfReady() {
        let snapshot = state.withLock {
            s -> (samples: [Float], context: OpaquePointer?, language: String, onLineCompleted: ((String) -> Void)?)? in
            guard !s.audioBuffer.isEmpty else { return nil }
            let reachedWindow = s.audioBuffer.count >= Self.windowSamples
            let gapElapsed: Bool
            if let last = s.lastAppendedAt {
                gapElapsed = Date().timeIntervalSince(last) >= Self.gapTimeout
            } else {
                gapElapsed = false
            }
            guard reachedWindow || gapElapsed else { return nil }

            let samples: [Float]
            if reachedWindow {
                samples = Array(s.audioBuffer.prefix(Self.windowSamples))
                s.audioBuffer.removeFirst(Self.windowSamples)
            } else {
                samples = s.audioBuffer
                s.audioBuffer.removeAll(keepingCapacity: false)
            }
            return (samples, s.context, s.language, s.onLineCompleted)
        }

        guard let snap = snapshot, let ctx = snap.context else { return }

        let text = runWhisper(context: ctx, samples: snap.samples, language: snap.language)
        let filtered = HallucinationFilter.filter(text)
        if !filtered.isEmpty {
            snap.onLineCompleted?(filtered)
        }
    }

    /// `whisper_full` を同期実行し、結果セグメントを連結したテキストを返す。
    /// context と language はロック内で取得済みのスナップショットを受け取る（ロック解放後に呼ぶ）。
    private func runWhisper(context ctx: OpaquePointer, samples: [Float], language: String) -> String {
        guard !samples.isEmpty else { return "" }

        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        let rms = sqrtf(meanSquare)
        guard rms > Self.silenceRmsThreshold else {
            Self.logger.debug("runWhisper skipped (rms=\(rms, privacy: .public) below silence threshold)")
            return ""
        }

        let result: Int32 = language.withCString { langPtr in
            // BEAM_SEARCH は GREEDY より hallucination（同一文字連続など）に強い
            var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
            params.beam_search.beam_size = 5
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.no_timestamps = true
            params.single_segment = false
            params.language = langPtr
            params.detect_language = false
            params.suppress_blank = true
            params.suppress_nst = true
            params.no_speech_thold = 0.6
            params.entropy_thold = 2.4
            params.temperature = 0.0
            params.temperature_inc = 0.2
            params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))

            return samples.withUnsafeBufferPointer { bufPtr -> Int32 in
                guard let base = bufPtr.baseAddress else { return -1 }
                return whisper_full(ctx, params, base, Int32(bufPtr.count))
            }
        }

        if result != 0 {
            Self.logger.error("whisper_full failed: code=\(result, privacy: .public)")
            handleRecognitionFailure(code: result)
            return ""
        }

        state.withLock { $0.consecutiveFailureCount = 0 }

        let segments = whisper_full_n_segments(ctx)
        var collected = ""
        for i in 0..<segments {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                collected += String(cString: cstr)
            }
        }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 連続失敗がしきい値を超えたら NotificationService 経由でユーザーに通知してカウンターをリセットする。
    /// 個別の失敗はログ＋空文字返却でサイレントに近いが、蓄積されて永続的な問題になっている場合は明示的に知らせる。
    private func handleRecognitionFailure(code: Int32) {
        let count = state.withLock { s -> Int in
            s.consecutiveFailureCount += 1
            return s.consecutiveFailureCount
        }
        guard count >= Self.consecutiveFailureThreshold else { return }
        state.withLock { $0.consecutiveFailureCount = 0 }
        Self.logger.fault("Kotoba 認識が \(count, privacy: .public) 回連続失敗、ユーザーに通知")
        let err = KuchibiError.modelLoadFailed(
            underlying: NSError(
                domain: "WhisperCppAdapter",
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "whisper_full が連続失敗しました (code=\(code))"]
            )
        )
        Task { [notificationService] in
            await notificationService?.sendErrorNotification(error: err)
        }
    }

    // MARK: - Test Hooks

    func _appendSamplesForTesting(_ samples: [Float], at date: Date = Date()) {
        state.withLock {
            $0.audioBuffer.append(contentsOf: samples)
            $0.lastAppendedAt = date
        }
    }

    func _bufferCountForTesting() -> Int {
        state.withLock { $0.audioBuffer.count }
    }

    func _hasContextForTesting() -> Bool {
        state.withLock { $0.context != nil }
    }

    enum _ReadyReason: Equatable {
        case window
        case gap
    }

    static func _selectReadySamples(
        buffer: inout [Float],
        lastAppendedAt: Date?,
        now: Date,
        windowSamples: Int = WhisperCppAdapter.windowSamples,
        gapTimeout: TimeInterval = WhisperCppAdapter.gapTimeout
    ) -> (samples: [Float], reason: _ReadyReason)? {
        guard !buffer.isEmpty else { return nil }
        let reachedWindow = buffer.count >= windowSamples
        let gapElapsed: Bool
        if let last = lastAppendedAt {
            gapElapsed = now.timeIntervalSince(last) >= gapTimeout
        } else {
            gapElapsed = false
        }
        guard reachedWindow || gapElapsed else { return nil }
        if reachedWindow {
            let window = Array(buffer.prefix(windowSamples))
            buffer.removeFirst(windowSamples)
            return (window, .window)
        }
        let all = buffer
        buffer.removeAll(keepingCapacity: false)
        return (all, .gap)
    }
}
