import Foundation

/// WhisperKit 経由で利用するモデル。
///
/// `rawValue` は WhisperKit 側で解決可能なモデル識別子とする。
/// `tiny` / `base` / `small` / `medium` は WhisperKit のショート名、
/// `largeV3Turbo` は HuggingFace 上の正式名称を用いる。
enum WhisperKitModel: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case tiny
    case base
    case small
    case medium
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        case .medium: "Medium"
        case .largeV3Turbo: "Large v3 Turbo"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny: "最速・低精度"
        case .base: "バランス型"
        case .small: "高精度・やや遅い"
        case .medium: "より高精度"
        case .largeV3Turbo: "最高精度・高速（推奨）"
        }
    }

    /// 旧 `WhisperModel.rawValue`（`tiny` / `base` / `small` / `medium` / `large-v2` / `large-v3`）から
    /// 新 `WhisperKitModel` に変換する。`large-v2` / `large-v3` は後継として `.largeV3Turbo` に集約する。
    /// 不明な値は nil を返す。`AppSettings` の `setting.modelName` → `setting.speechEngine` migration で使用する。
    init?(fromLegacy rawValue: String) {
        switch rawValue {
        case "tiny": self = .tiny
        case "base": self = .base
        case "small": self = .small
        case "medium": self = .medium
        case "large-v2", "large-v3": self = .largeV3Turbo
        default: return nil
        }
    }
}

/// Kotoba-Whisper Bilingual v1（whisper.cpp GGML 量子化モデル）。
///
/// `rawValue` = `expectedFileName` とし、`ModelAvailabilityChecker` が
/// ファイル存在判定に用いる。モデルは HuggingFace から手動で取得してもらう運用のため、
/// `downloadPageURL` でモデルページへの導線を提供する。
enum KotobaWhisperBilingualModel: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case v1Q5 = "ggml-kotoba-whisper-bilingual-v1.0-q5_0.bin"
    case v1Full = "ggml-kotoba-whisper-bilingual-v1.0.bin"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v1Q5: "Kotoba Bilingual v1 (Q5_0 量子化)"
        case .v1Full: "Kotoba Bilingual v1 (Full)"
        }
    }

    /// `ModelAvailabilityChecker` が参照する期待ファイル名（配置先ディレクトリ配下の basename）
    var expectedFileName: String { rawValue }

    /// HuggingFace モデルページ URL（UI の「モデルページを開く」導線で使用）
    var downloadPageURL: URL {
        // Kotoba-Whisper Bilingual v1 の公開ページ
        // 量子化バリアント間で共通のモデルページを指す
        URL(string: "https://huggingface.co/kotoba-tech/kotoba-whisper-bilingual-v1.0-ggml")!
    }
}
