import Foundation

/// アプリケーション全体のエラー型
enum KuchibiError: Error {
    case modelLoadFailed(underlying: Error)
    case microphonePermissionDenied
    case microphoneUnavailable
    case recognitionFailed(underlying: Error)
    case accessibilityPermissionDenied
}
