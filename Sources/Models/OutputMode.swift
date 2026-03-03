/// テキスト出力モード（UserDefaultsに永続化するためRawRepresentable）
enum OutputMode: String, Equatable, Sendable {
    case clipboard
    case directInput
}
