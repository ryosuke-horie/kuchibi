import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

/// `WhisperCppAdapter` の単体テスト。
///
/// 注意:
/// - 実モデルファイル（GGML 重み）はリポジトリに含まれないため、`whisper_full` の
///   推論経路は本テストでは検証しない（統合テスト 9.x に委譲）。
/// - 純粋な Swift で完結するロジック（gap detection / window 切り出し / engineMismatch /
///   modelFileMissing throw / コンテキスト解放後の状態管理）に焦点を絞る。
@Suite("WhisperCppAdapter")
struct WhisperCppAdapterTests {
    // MARK: - filterHallucination

    @Test("hallucination フィルタ: 同一文字連続は空文字を返す")
    func filterHallucinationDropsRepeatedCharacters() {
        #expect(WhisperCppAdapter.filterHallucination("aaaaaaaaaaaaaaa") == "")
        #expect(WhisperCppAdapter.filterHallucination("あああああああああ") == "")
        #expect(WhisperCppAdapter.filterHallucination("....................") == "")
    }

    @Test("hallucination フィルタ: 通常テキストは保持する")
    func filterHallucinationPreservesNormalText() {
        #expect(WhisperCppAdapter.filterHallucination("こんにちは、世界") == "こんにちは、世界")
        #expect(WhisperCppAdapter.filterHallucination("Hello world") == "Hello world")
        // 短いテキストはそのまま通す
        #expect(WhisperCppAdapter.filterHallucination("あ") == "あ")
        #expect(WhisperCppAdapter.filterHallucination("aaaa") == "aaaa")  // 5 未満は保持
    }

    @Test("hallucination フィルタ: 前後の空白は trim される")
    func filterHallucinationTrimsWhitespace() {
        #expect(WhisperCppAdapter.filterHallucination("  こんにちは  ") == "こんにちは")
        #expect(WhisperCppAdapter.filterHallucination("\n\n\naaaaaaaaaaa\n\n") == "")
    }

    @Test("hallucination フィルタ: 一部重複は許容（60% 未満なら保持）")
    func filterHallucinationKeepsPartialRepetition() {
        // 短い連続は phrase として正常（「ああ、そうですか」など）
        let text = "ああ、そうですか"
        #expect(WhisperCppAdapter.filterHallucination(text) == text)
    }


    // MARK: - initialize: エンジン不一致 / モデル未配置

    @Test("非 Kotoba エンジン (.whisperKit) を渡すと engineMismatch を throw する")
    func initializeRejectsWhisperKitEngine() async {
        let availability = MockModelAvailabilityChecker()
        let adapter = WhisperCppAdapter(availability: availability)

        do {
            try await adapter.initialize(engine: .whisperKit(.base), language: "ja")
            Issue.record("Expected KuchibiError.engineMismatch but no error was thrown")
        } catch let error as KuchibiError {
            switch error {
            case .engineMismatch(let expected, let actual):
                if case .kotobaWhisperBilingual = expected {
                    // expected は kotobaWhisperBilingual 系であれば OK
                } else {
                    Issue.record("Expected expected to be .kotobaWhisperBilingual, got \(expected)")
                }
                #expect(actual == .whisperKit(.base))
            default:
                Issue.record("Expected .engineMismatch, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("modelPath が nil のとき modelFileMissing を throw する")
    func initializeThrowsWhenModelPathIsNil() async {
        let availability = MockModelAvailabilityChecker()
        // `pathOverride` 未設定 → MockModelAvailabilityChecker は nil を返す
        let adapter = WhisperCppAdapter(availability: availability)

        do {
            try await adapter.initialize(
                engine: .kotobaWhisperBilingual(.v1Q5),
                language: "ja"
            )
            Issue.record("Expected KuchibiError.modelFileMissing but no error was thrown")
        } catch let error as KuchibiError {
            if case .modelFileMissing = error {
                // OK
            } else {
                Issue.record("Expected .modelFileMissing, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("modelPath が存在しないファイルを指すとき modelFileMissing を throw する")
    func initializeThrowsWhenModelFileDoesNotExist() async {
        let availability = MockModelAvailabilityChecker()
        let nonExistent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kuchibi-test-nonexistent-\(UUID().uuidString).bin")
        availability.pathOverride[.kotobaWhisperBilingual(.v1Q5)] = nonExistent

        let adapter = WhisperCppAdapter(availability: availability)

        do {
            try await adapter.initialize(
                engine: .kotobaWhisperBilingual(.v1Q5),
                language: "ja"
            )
            Issue.record("Expected KuchibiError.modelFileMissing but no error was thrown")
        } catch let error as KuchibiError {
            switch error {
            case .modelFileMissing(let path):
                #expect(path == nonExistent.path)
            default:
                Issue.record("Expected .modelFileMissing, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - finalize 後の状態管理

    @Test("初期化失敗時は finalize 後も context が nil のまま")
    func contextRemainsNilAfterFailedInitialize() async {
        let availability = MockModelAvailabilityChecker()
        let adapter = WhisperCppAdapter(availability: availability)

        try? await adapter.initialize(
            engine: .kotobaWhisperBilingual(.v1Q5),
            language: "ja"
        )
        #expect(adapter._hasContextForTesting() == false)

        // finalize は context が無い状態でも安全に呼べる
        let text = await adapter.finalize()
        #expect(text.isEmpty)
        #expect(adapter._hasContextForTesting() == false)
    }

    @Test("startStream は initialize 前に呼ぶと throw する")
    func startStreamThrowsBeforeInitialize() {
        let adapter = WhisperCppAdapter(availability: MockModelAvailabilityChecker())
        do {
            try adapter.startStream(onTextChanged: { _ in }, onLineCompleted: { _ in })
            Issue.record("Expected throw but startStream succeeded")
        } catch let error as KuchibiError {
            if case .modelLoadFailed = error {
                // OK
            } else {
                Issue.record("Expected .modelLoadFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("getPartialText は擬似ストリーミング中も常に空文字列を返す")
    func getPartialTextAlwaysEmpty() {
        let adapter = WhisperCppAdapter(availability: MockModelAvailabilityChecker())
        adapter._appendSamplesForTesting([0.1, 0.2, 0.3])
        #expect(adapter.getPartialText() == "")
    }

    @Test("finalize 後に再 initialize が試行可能（modelFileMissing はもう一度 throw される）")
    func reinitializeAfterFinalize() async {
        let availability = MockModelAvailabilityChecker()
        availability.pathOverride[.kotobaWhisperBilingual(.v1Q5)] = URL(
            fileURLWithPath: "/tmp/kuchibi-nonexistent-\(UUID().uuidString).bin"
        )
        let adapter = WhisperCppAdapter(availability: availability)

        // 1 回目: ファイル無しで失敗
        do {
            try await adapter.initialize(
                engine: .kotobaWhisperBilingual(.v1Q5),
                language: "ja"
            )
            Issue.record("Expected initial throw")
        } catch {
            // 期待通り
        }
        _ = await adapter.finalize()
        #expect(adapter._hasContextForTesting() == false)

        // 2 回目: 同じく throw され、状態が壊れていない
        do {
            try await adapter.initialize(
                engine: .kotobaWhisperBilingual(.v1Q5),
                language: "en"
            )
            Issue.record("Expected re-initialize throw")
        } catch let error as KuchibiError {
            if case .modelFileMissing = error {
                // OK: 状態壊れず再 initialize でも同じ理由で throw
            } else {
                Issue.record("Expected .modelFileMissing on re-initialize, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - addAudio: バッファ蓄積

    @Test("addAudio は 16kHz mono Float32 サンプルを内部バッファへ蓄積する")
    func addAudioAccumulatesSamples() {
        let adapter = WhisperCppAdapter(availability: MockModelAvailabilityChecker())
        let buffer = makePCMBuffer(samples: Array(repeating: Float(0.1), count: 1_600))
        adapter.addAudio(buffer)
        #expect(adapter._bufferCountForTesting() == 1_600)

        adapter.addAudio(buffer)
        #expect(adapter._bufferCountForTesting() == 3_200)
    }

    // MARK: - リングバッファ / gap detection 純粋ロジック

    @Test("バッファが空のとき _selectReadySamples は nil を返す")
    func selectReadyReturnsNilWhenEmpty() {
        var buffer: [Float] = []
        let result = WhisperCppAdapter._selectReadySamples(
            buffer: &buffer,
            lastAppendedAt: Date(),
            now: Date()
        )
        #expect(result == nil)
    }

    @Test("バッファが 30 秒未満かつ gap も短ければ nil を返す")
    func selectReadyReturnsNilBeforeWindowOrGap() {
        var buffer: [Float] = Array(repeating: 0, count: 100)
        let now = Date()
        let result = WhisperCppAdapter._selectReadySamples(
            buffer: &buffer,
            lastAppendedAt: now,
            now: now
        )
        #expect(result == nil)
        #expect(buffer.count == 100)  // バッファはそのまま
    }

    @Test("gap が gapTimeout を超えたとき全バッファを取り出してクリアする (.gap)")
    func selectReadyOnGapExtractsAll() {
        var buffer: [Float] = Array(repeating: Float(0.5), count: 5_000)
        let now = Date()
        let lastAppended = now.addingTimeInterval(-2.0)  // 2 秒前
        guard let result = WhisperCppAdapter._selectReadySamples(
            buffer: &buffer,
            lastAppendedAt: lastAppended,
            now: now
        ) else {
            Issue.record("Expected ready samples")
            return
        }
        #expect(result.reason == .gap)
        #expect(result.samples.count == 5_000)
        #expect(buffer.isEmpty)
    }

    @Test("30 秒窓に到達したとき先頭 30 秒を取り出し、残りはバッファに残す (.window)")
    func selectReadyOnWindowExtractsFirstWindow() {
        let windowSize = 30 * 16_000
        var buffer: [Float] = Array(repeating: Float(0.5), count: windowSize + 4_000)
        let now = Date()
        guard let result = WhisperCppAdapter._selectReadySamples(
            buffer: &buffer,
            lastAppendedAt: now,
            now: now
        ) else {
            Issue.record("Expected ready samples")
            return
        }
        #expect(result.reason == .window)
        #expect(result.samples.count == windowSize)
        #expect(buffer.count == 4_000)  // 残り
    }

    @Test("lastAppendedAt が nil なら gap 判定は発火しない")
    func selectReadyDoesNotFireGapWhenLastAppendedIsNil() {
        var buffer: [Float] = Array(repeating: 0, count: 100)
        let result = WhisperCppAdapter._selectReadySamples(
            buffer: &buffer,
            lastAppendedAt: nil,
            now: Date().addingTimeInterval(60)
        )
        #expect(result == nil)
    }

    // MARK: - Helpers

    private func makePCMBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = samples[i]
            }
        }
        return buffer
    }
}
