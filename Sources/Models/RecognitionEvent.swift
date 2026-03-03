/// 音声認識イベント
struct RecognitionEvent {
    enum Kind: Equatable {
        case lineStarted
        case textChanged(partial: String)
        case lineCompleted(final: String)
    }
    let kind: Kind
}
