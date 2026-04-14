import Foundation
import Testing
@testable import Kuchibi

@Suite("SpeechEngine")
struct SpeechEngineTests {
    // MARK: - SpeechEngineKind

    @Test("SpeechEngineKind: allCases が 2 件で rawValue が一致する")
    func speechEngineKindAllCases() {
        let kinds = SpeechEngineKind.allCases
        #expect(kinds.count == 2)
        #expect(kinds.contains(.whisperKit))
        #expect(kinds.contains(.kotobaWhisperBilingual))
        #expect(SpeechEngineKind.whisperKit.rawValue == "whisperKit")
        #expect(SpeechEngineKind.kotobaWhisperBilingual.rawValue == "kotobaWhisperBilingual")
    }

    @Test("SpeechEngineKind: displayName が非空")
    func speechEngineKindDisplayName() {
        for kind in SpeechEngineKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("SpeechEngineKind: id が rawValue と一致する")
    func speechEngineKindID() {
        #expect(SpeechEngineKind.whisperKit.id == "whisperKit")
        #expect(SpeechEngineKind.kotobaWhisperBilingual.id == "kotobaWhisperBilingual")
    }

    // MARK: - WhisperKitModel

    @Test("WhisperKitModel: 5 ケースの rawValue")
    func whisperKitModelRawValues() {
        #expect(WhisperKitModel.tiny.rawValue == "tiny")
        #expect(WhisperKitModel.base.rawValue == "base")
        #expect(WhisperKitModel.small.rawValue == "small")
        #expect(WhisperKitModel.medium.rawValue == "medium")
        #expect(WhisperKitModel.largeV3Turbo.rawValue == "openai_whisper-large-v3-v20240930_turbo")
        #expect(WhisperKitModel.allCases.count == 5)
    }

    @Test("WhisperKitModel: displayName / sizeDescription が非空")
    func whisperKitModelDisplayNames() {
        for model in WhisperKitModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.sizeDescription.isEmpty)
        }
    }

    // MARK: - KotobaWhisperBilingualModel

    @Test("KotobaWhisperBilingualModel: 2 ケースの rawValue / expectedFileName")
    func kotobaModelRawValues() {
        #expect(KotobaWhisperBilingualModel.v1Q5.rawValue == "ggml-kotoba-whisper-bilingual-v1.0-q5_0.bin")
        #expect(KotobaWhisperBilingualModel.v1Q8.rawValue == "ggml-kotoba-whisper-bilingual-v1.0-q8_0.bin")
        #expect(KotobaWhisperBilingualModel.v1Q5.expectedFileName == KotobaWhisperBilingualModel.v1Q5.rawValue)
        #expect(KotobaWhisperBilingualModel.v1Q8.expectedFileName == KotobaWhisperBilingualModel.v1Q8.rawValue)
        #expect(KotobaWhisperBilingualModel.allCases.count == 2)
    }

    @Test("KotobaWhisperBilingualModel: downloadPageURL が HuggingFace を指す")
    func kotobaDownloadPageURL() {
        for model in KotobaWhisperBilingualModel.allCases {
            let url = model.downloadPageURL
            #expect(url.scheme == "https")
            #expect(url.host?.contains("huggingface.co") == true)
        }
    }

    @Test("KotobaWhisperBilingualModel: displayName が非空")
    func kotobaDisplayName() {
        for model in KotobaWhisperBilingualModel.allCases {
            #expect(!model.displayName.isEmpty)
        }
    }

    // MARK: - SpeechEngine 基本

    @Test("SpeechEngine.kind は associated value に対応する")
    func speechEngineKind() {
        #expect(SpeechEngine.whisperKit(.base).kind == .whisperKit)
        #expect(SpeechEngine.kotobaWhisperBilingual(.v1Q5).kind == .kotobaWhisperBilingual)
    }

    @Test("SpeechEngine.engineDisplayName / modelDisplayName が非空")
    func speechEngineDisplayNames() {
        let cases: [SpeechEngine] = [
            .whisperKit(.tiny),
            .whisperKit(.base),
            .whisperKit(.small),
            .whisperKit(.medium),
            .whisperKit(.largeV3Turbo),
            .kotobaWhisperBilingual(.v1Q5),
            .kotobaWhisperBilingual(.v1Q8),
        ]
        for engine in cases {
            #expect(!engine.engineDisplayName.isEmpty)
            #expect(!engine.modelDisplayName.isEmpty)
            #expect(!engine.modelIdentifier.isEmpty)
        }
    }

    @Test("SpeechEngine の Equatable/Hashable が associated value を区別する")
    func speechEngineEquatableHashable() {
        #expect(SpeechEngine.whisperKit(.base) == SpeechEngine.whisperKit(.base))
        #expect(SpeechEngine.whisperKit(.base) != SpeechEngine.whisperKit(.tiny))
        #expect(SpeechEngine.whisperKit(.base) != SpeechEngine.kotobaWhisperBilingual(.v1Q5))

        var set: Set<SpeechEngine> = []
        set.insert(.whisperKit(.base))
        set.insert(.whisperKit(.base))
        set.insert(.whisperKit(.tiny))
        set.insert(.kotobaWhisperBilingual(.v1Q5))
        #expect(set.count == 3)
    }

    // MARK: - Codable ラウンドトリップ — Req 1.3

    @Test("SpeechEngine: whisperKit 各モデルで Codable ラウンドトリップが同値を返す")
    func codableRoundtripWhisperKit() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for model in WhisperKitModel.allCases {
            let original = SpeechEngine.whisperKit(model)
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(SpeechEngine.self, from: data)
            #expect(decoded == original, "roundtrip failed for whisperKit(\(model))")
        }
    }

    @Test("SpeechEngine: kotobaWhisperBilingual 各モデルで Codable ラウンドトリップが同値を返す")
    func codableRoundtripKotoba() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for model in KotobaWhisperBilingualModel.allCases {
            let original = SpeechEngine.kotobaWhisperBilingual(model)
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(SpeechEngine.self, from: data)
            #expect(decoded == original, "roundtrip failed for kotobaWhisperBilingual(\(model))")
        }
    }

    @Test("SpeechEngine: Codable JSON が discriminator kind と model を含む")
    func codableJSONShape() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(SpeechEngine.whisperKit(.largeV3Turbo))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["kind"] as? String == "whisperKit")
        #expect(json?["model"] as? String == "openai_whisper-large-v3-v20240930_turbo")
    }

    @Test("SpeechEngine: requiresRestartOnSwitch は現状 false")
    func requiresRestartOnSwitchIsFalse() {
        for engine in [SpeechEngine.whisperKit(.base), SpeechEngine.kotobaWhisperBilingual(.v1Q5)] {
            #expect(engine.requiresRestartOnSwitch == false)
        }
    }
}
