/// 音声入力セッションの状態
enum SessionState: Equatable {
    case idle
    case recording
    case processing
}
