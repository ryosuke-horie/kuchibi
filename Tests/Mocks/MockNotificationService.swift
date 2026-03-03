@testable import Kuchibi

final class MockNotificationService: NotificationServicing {
    var sentNotifications: [(title: String, body: String)] = []
    var sentErrors: [KuchibiError] = []

    func sendNotification(title: String, body: String) async {
        sentNotifications.append((title: title, body: body))
    }

    func sendErrorNotification(error: KuchibiError) async {
        sentErrors.append(error)
    }
}
