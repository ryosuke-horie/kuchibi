import Foundation

/// アプリケーション全体のエラー型
enum KuchibiError: Error, LocalizedError {
    case modelLoadFailed(underlying: Error)
    case microphonePermissionDenied
    case microphoneUnavailable
    case recognitionFailed(underlying: Error)
    case accessibilityPermissionDenied
    /// アダプターに想定外のエンジンが渡された（例: WhisperKitAdapter に kotobaWhisperBilingual が渡された）
    case engineMismatch(expected: SpeechEngine, actual: SpeechEngine)
    /// モデルファイルがディスク上に存在しない
    case modelFileMissing(path: String)
    /// 録音中または処理中にエンジン切替が要求された
    case sessionActiveDuringSwitch

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let underlying):
            return "モデルの読み込みに失敗しました: \(underlying.localizedDescription)"
        case .microphonePermissionDenied:
            return "マイクのアクセス権限が許可されていません"
        case .microphoneUnavailable:
            return "マイクが利用できません"
        case .recognitionFailed(let underlying):
            return "音声認識に失敗しました: \(underlying.localizedDescription)"
        case .accessibilityPermissionDenied:
            return "アクセシビリティ権限が許可されていません"
        case .engineMismatch(let expected, let actual):
            return "エンジンの不一致: 期待 \(expected.engineDisplayName)、受信 \(actual.engineDisplayName)"
        case .modelFileMissing(let path):
            return "モデルファイルが見つかりません: \(path)"
        case .sessionActiveDuringSwitch:
            return "録音中または処理中のためエンジン切替を適用できません"
        }
    }
}
