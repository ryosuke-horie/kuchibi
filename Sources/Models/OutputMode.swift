/// テキスト出力モード（UserDefaultsに永続化するためRawRepresentable）
enum OutputMode: String, Equatable {
    case clipboard
    case directInput
}
