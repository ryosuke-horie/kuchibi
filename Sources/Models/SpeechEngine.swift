import Foundation

/// 音声認識エンジンと、そのエンジンで利用するモデルを型安全に表現する。
///
/// 永続化フォーマットは discriminator 付き JSON:
/// ```json
/// { "kind": "whisperKit", "model": "base" }
/// { "kind": "kotobaWhisperBilingual", "model": "ggml-kotoba-whisper-bilingual-v1.0-q5_0.bin" }
/// ```
/// 将来 SenseVoice 等の追加時は新しい case と対応 `EngineModel` enum を追加するのみで済む。
enum SpeechEngine: Equatable, Hashable, Codable, Sendable {
    case whisperKit(WhisperKitModel)
    case kotobaWhisperBilingual(KotobaWhisperBilingualModel)

    // MARK: - Derived Properties

    /// UI 列挙用の種別キー
    var kind: SpeechEngineKind {
        switch self {
        case .whisperKit: .whisperKit
        case .kotobaWhisperBilingual: .kotobaWhisperBilingual
        }
    }

    /// エンジン名（設定 UI の Picker ラベル等に使用）
    var engineDisplayName: String { kind.displayName }

    /// モデル名（設定 UI の Picker ラベル等に使用）
    var modelDisplayName: String {
        switch self {
        case .whisperKit(let model): model.displayName
        case .kotobaWhisperBilingual(let model): model.displayName
        }
    }

    /// ログ・識別に用いる短い識別子
    var modelIdentifier: String {
        switch self {
        case .whisperKit(let model): "whisperKit/\(model.rawValue)"
        case .kotobaWhisperBilingual(let model): "kotobaWhisperBilingual/\(model.rawValue)"
        }
    }

    /// 切替に再起動が本質的に必要なエンジンかどうか。現状はいずれも hot-swap 可能なため false。
    /// 将来 hot-swap できないエンジンを追加する際にこのプロパティで分岐する。
    var requiresRestartOnSwitch: Bool { false }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SpeechEngineKind.self, forKey: .kind)
        let modelRaw = try container.decode(String.self, forKey: .model)

        switch kind {
        case .whisperKit:
            guard let model = WhisperKitModel(rawValue: modelRaw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .model,
                    in: container,
                    debugDescription: "Unknown WhisperKitModel rawValue: \(modelRaw)"
                )
            }
            self = .whisperKit(model)
        case .kotobaWhisperBilingual:
            guard let model = KotobaWhisperBilingualModel(rawValue: modelRaw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .model,
                    in: container,
                    debugDescription: "Unknown KotobaWhisperBilingualModel rawValue: \(modelRaw)"
                )
            }
            self = .kotobaWhisperBilingual(model)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .whisperKit(let model):
            try container.encode(model.rawValue, forKey: .model)
        case .kotobaWhisperBilingual(let model):
            try container.encode(model.rawValue, forKey: .model)
        }
    }
}

/// UI で列挙するためのエンジン種別キー。
///
/// `SpeechEngine` の associated value を持たないフラット表現で、
/// Picker の選択候補や `allCases` 列挙に用いる。
enum SpeechEngineKind: String, CaseIterable, Identifiable, Codable, Equatable, Hashable, Sendable {
    case whisperKit
    case kotobaWhisperBilingual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperKit: "WhisperKit"
        case .kotobaWhisperBilingual: "Kotoba-Whisper Bilingual"
        }
    }
}
