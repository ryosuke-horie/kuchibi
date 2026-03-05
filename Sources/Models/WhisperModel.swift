/// WhisperKit で利用可能なモデルサイズ
enum WhisperModel: String, CaseIterable, Identifiable, Equatable, Sendable {
    case tiny
    case base
    case small
    case medium
    case largeV2 = "large-v2"
    case largeV3 = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        case .medium: "Medium"
        case .largeV2: "Large v2"
        case .largeV3: "Large v3"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny: "最速・低精度"
        case .base: "バランス型"
        case .small: "高精度・やや遅い"
        case .medium: "より高精度"
        case .largeV2: "最高精度（メモリ大）"
        case .largeV3: "最高精度（メモリ大）"
        }
    }
}
