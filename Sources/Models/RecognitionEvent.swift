/// 音声認識イベント
struct RecognitionEvent: Sendable {
    enum Kind: Equatable, Sendable {
        case lineStarted
        case textChanged(partial: String)
        case lineCompleted(final: String)
    }
    let kind: Kind
}
