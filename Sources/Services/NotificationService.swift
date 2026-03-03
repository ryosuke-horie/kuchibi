import UserNotifications
import os

/// macOS通知センターへの通知送信サービス
final class NotificationServiceImpl: NotificationServicing {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "Notification")

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("通知権限の取得に失敗: \(error.localizedDescription)")
            }
        }
    }

    func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.error("通知の送信に失敗: \(error.localizedDescription)")
        }
    }

    func sendErrorNotification(error: KuchibiError) async {
        let (title, body) = notificationContent(for: error)
        await sendNotification(title: title, body: body)
    }

    func notificationContent(for error: KuchibiError) -> (title: String, body: String) {
        switch error {
        case .modelLoadFailed(let underlying):
            return ("モデル読み込みエラー", "音声認識モデルの読み込みに失敗しました: \(underlying.localizedDescription)")
        case .microphonePermissionDenied:
            return ("マイク権限エラー", "システム設定 > プライバシーとセキュリティ > マイク からアクセスを許可してください")
        case .microphoneUnavailable:
            return ("マイクエラー", "マイクが利用できません。接続を確認してください")
        case .recognitionFailed(let underlying):
            return ("認識エラー", "音声認識中にエラーが発生しました: \(underlying.localizedDescription)")
        case .accessibilityPermissionDenied:
            return ("アクセシビリティ権限エラー", "システム設定 > プライバシーとセキュリティ > アクセシビリティ からアクセスを許可してください")
        case .silenceTimeout:
            return ("タイムアウト", "音声が検出されなかったため、セッションを終了しました")
        }
    }
}
