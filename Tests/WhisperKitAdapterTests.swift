import Foundation
import Testing
@testable import Kuchibi

/// `WhisperKitAdapter` の薄いユニットテスト。
///
/// 注意:
/// - WhisperKit 実モデルのロードはネットワーク DL を伴うため、ユニットテストでは行わない。
/// - 本テストではエンジン不一致時の早期 `throw`、および `largeV3Turbo` の rawValue が
///   想定通り（`openai_whisper-large-v3-v20240930_turbo`）であることのみを検証する。
@Suite("WhisperKitAdapter")
struct WhisperKitAdapterTests {
    @Test("WhisperKitModel.largeV3Turbo の rawValue は HuggingFace 上のモデル名と一致する")
    func largeV3TurboRawValue() {
        #expect(WhisperKitModel.largeV3Turbo.rawValue == "openai_whisper-large-v3-v20240930_turbo")
    }

    @Test("非 WhisperKit エンジン (.kotobaWhisperBilingual) を渡すと engineMismatch を throw する")
    func initializeRejectsKotobaEngine() async {
        let adapter = WhisperKitAdapter()
        do {
            try await adapter.initialize(
                engine: .kotobaWhisperBilingual(.v1Q5),
                language: "ja"
            )
            Issue.record("Expected KuchibiError.engineMismatch but no error was thrown")
        } catch let error as KuchibiError {
            switch error {
            case .engineMismatch(let expected, let actual):
                if case .whisperKit = expected {
                    // expected は WhisperKit 系であれば OK
                } else {
                    Issue.record("Expected expected to be .whisperKit, got \(expected)")
                }
                #expect(actual == .kotobaWhisperBilingual(.v1Q5))
            default:
                Issue.record("Expected .engineMismatch, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("largeV3Turbo の SpeechEngine 値が型安全に組み立てられる")
    func largeV3TurboSpeechEngineConstruction() {
        let engine: SpeechEngine = .whisperKit(.largeV3Turbo)
        // identifier に rawValue が含まれる（ログ出力との同期確認）
        #expect(engine.modelIdentifier.contains("openai_whisper-large-v3-v20240930_turbo"))
        #expect(engine.kind == .whisperKit)
    }
}
