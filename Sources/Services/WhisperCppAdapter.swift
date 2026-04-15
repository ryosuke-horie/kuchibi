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
///    確定テキストを `onLineCompleted` で通知してリングバッファをクリアする（窓境界では
///    コンテキストを prompt-shift せず単純リセット = 整合性優先）。
/// 5. `finalize()` で残バッファを `whisper_full` で処理して結果を返し、`whisper_free` で
///    コンテキストを解放する（リーク防止）。再 `initialize` で再利用可能。
///
/// 注: WhisperKitAdapter とは異なり、`onTextChanged`（部分テキスト）は擬似ストリーミング
/// では非対応のため、`getPartialText()` は常に空文字列を返す。
///
/// 並行安全性: 内部状態（`audioBuffer` / `lastAppendedAt` 等）は `OSAllocatedUnfairLock` で
/// 保護し、`context` は initialize/finalize/deinit 以外では read-only。`whisper_full` は
/// `processingTask` 上で同期実行されるが、`Task.detached` で協調スレッドプールに逃がす
/// ことで MainActor を数百 ms〜数秒ブロックしない（UI の音量バーが固まる問題を回避）。
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

    private let availability: ModelAvailabilityChecking

    /// whisper コンテキスト。`initialize` でセットし `finalize` で `whisper_free` する。
    /// 並行アクセスは想定しないが、ライフサイクルメソッドが順序通り呼ばれることを前提とする。
    private var context: OpaquePointer?
    private var currentLanguage: String = "ja"

    /// 内部状態。`OSAllocatedUnfairLock` で保護する。
    private struct State {
        var audioBuffer: [Float] = []
        var lastAppendedAt: Date?
        var isFinalized: Bool = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var processingTask: Task<Void, Never>?
    private var onTextChanged: ((String) -> Void)?
    private var onLineCompleted: ((String) -> Void)?

    init(availability: ModelAvailabilityChecking = ModelAvailabilityChecker()) {
        self.availability = availability
    }

    deinit {
        // セーフティネット: finalize 漏れ時にもリークを防ぐ
        if let context {
            whisper_free(context)
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
        if let existing = context {
            whisper_free(existing)
            context = nil
        }

        guard let path = availability.modelPath(for: engine) else {
            throw KuchibiError.modelFileMissing(path: "unknown")
        }
        guard FileManager.default.fileExists(atPath: path.path) else {
            Self.logger.error("Kotoba モデル未配置: \(path.path, privacy: .public)")
            throw KuchibiError.modelFileMissing(path: path.path)
        }

        currentLanguage = language

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
        context = ctx
        Self.logger.info(
            "whisper.cpp モデル '\(engine.modelIdentifier, privacy: .public)' を言語 '\(language, privacy: .public)' で読み込み完了"
        )
    }

    func startStream(
        onTextChanged: @escaping (String) -> Void,
        onLineCompleted: @escaping (String) -> Void
    ) throws {
        guard context != nil else {
            throw KuchibiError.modelLoadFailed(
                underlying: NSError(
                    domain: "WhisperCppAdapter",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "モデルが初期化されていません"]
                )
            )
        }

        state.withLock { $0 = State() }
        self.onTextChanged = onTextChanged
        self.onLineCompleted = onLineCompleted

        // 過去の Task が残っていれば停止
        processingTask?.cancel()

        // `whisper_full` は同期 C 関数で数百 ms〜数秒ブロックするため、
        // `Task.detached` で MainActor から切り離し、協調スレッドプールで実行する。
        // 呼び出し側の `processAudioStream` が MainActor 由来の場合でも、
        // UI スレッド（音量バーの更新等）をブロックしない。
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
        // 1. processingTask を停止して並行実行を防ぐ
        processingTask?.cancel()
        await processingTask?.value
        processingTask = nil

        // 2. 残バッファを取り出してクリア
        let leftover = state.withLock { s -> [Float] in
            let buf = s.audioBuffer
            s.audioBuffer.removeAll(keepingCapacity: false)
            // isFinalized は使われていない旧フラグなので false のまま（複数録音継続のため）
            s.isFinalized = false
            return buf
        }

        // 3. 残バッファを処理（gap 確定で先に通知済みの場合は空になっている）
        var finalText = ""
        if !leftover.isEmpty, context != nil {
            finalText = runWhisper(samples: leftover)
            if !finalText.isEmpty {
                onLineCompleted?(finalText)
            }
        }

        // 4. コールバック参照を解除（同一 adapter を次録音で再利用するため context は解放しない）
        onTextChanged = nil
        onLineCompleted = nil

        // コンテキストはここでは解放しない:
        // - 次の `startStream` で同じコンテキストを再利用する（モデル再ロードを避ける）
        // - switchEngine で別 adapter に差し替えられた時は deinit が `whisper_free` を呼ぶ
        // - 同一 engine への再 initialize 時は冒頭で旧コンテキストを free する

        return finalText
    }

    // MARK: - Private

    /// `processingTask` から定期的に呼ばれる。確定すべき条件を満たしていれば
    /// `whisper_full` を同期実行して `onLineCompleted` を発火し、バッファをクリアする。
    private func tickAndProcessIfReady() {
        let snapshot: [Float]? = state.withLock { s -> [Float]? in
            guard !s.audioBuffer.isEmpty else { return nil }
            let reachedWindow = s.audioBuffer.count >= Self.windowSamples
            let gapElapsed: Bool
            if let last = s.lastAppendedAt {
                gapElapsed = Date().timeIntervalSince(last) >= Self.gapTimeout
            } else {
                gapElapsed = false
            }
            guard reachedWindow || gapElapsed else { return nil }
            // 30 秒以上溜まっていたら 30 秒分だけ取り出す（窓境界で context は持ち越さない）
            if reachedWindow {
                let window = Array(s.audioBuffer.prefix(Self.windowSamples))
                s.audioBuffer.removeFirst(Self.windowSamples)
                return window
            }
            // gap 起因の確定時はバッファ全体を取り出してクリア
            let all = s.audioBuffer
            s.audioBuffer.removeAll(keepingCapacity: false)
            return all
        }

        guard let samples = snapshot else { return }

        let text = runWhisper(samples: samples)
        if !text.isEmpty {
            onLineCompleted?(text)
        }
    }

    /// `whisper_full` を同期実行し、結果セグメントを連結したテキストを返す。
    /// `language` は C string をスコープ内に保持するために `withCString` を使う。
    func runWhisper(samples: [Float]) -> String {
        guard let ctx = context else { return "" }
        guard !samples.isEmpty else { return "" }

        return currentLanguage.withCString { langPtr -> String in
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.no_timestamps = true
            params.single_segment = false
            params.language = langPtr
            params.detect_language = false
            params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))

            let result = samples.withUnsafeBufferPointer { bufPtr -> Int32 in
                guard let base = bufPtr.baseAddress else { return -1 }
                return whisper_full(ctx, params, base, Int32(bufPtr.count))
            }

            guard result == 0 else {
                Self.logger.error("whisper_full failed: code=\(result, privacy: .public)")
                return ""
            }

            let segments = whisper_full_n_segments(ctx)
            var collected = ""
            for i in 0..<segments {
                if let cstr = whisper_full_get_segment_text(ctx, i) {
                    collected += String(cString: cstr)
                }
            }
            return collected.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Test Hooks

    /// テスト用: 内部バッファに直接 Float サンプルを追加する。`addAudio` が
    /// `AVAudioPCMBuffer` を要求するため、純粋な Swift テストでは利用しづらい。
    func _appendSamplesForTesting(_ samples: [Float], at date: Date = Date()) {
        state.withLock {
            $0.audioBuffer.append(contentsOf: samples)
            $0.lastAppendedAt = date
        }
    }

    /// テスト用: 現在の内部バッファサイズ
    func _bufferCountForTesting() -> Int {
        state.withLock { $0.audioBuffer.count }
    }

    /// テスト用: コンテキストが保持されているかどうか
    func _hasContextForTesting() -> Bool {
        context != nil
    }

    /// テスト用: gap detection / window 切り出しロジックを純粋に検証するための
    /// バッファ取り出しヘルパー。`tickAndProcessIfReady` の最初のステップと等価。
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
