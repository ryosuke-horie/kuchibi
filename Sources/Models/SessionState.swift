/// 音声入力セッションの状態
enum SessionState: Equatable, Sendable {
    case idle
    case recording
    case processing
}
