/// macOS通知サービスのプロトコル
protocol NotificationServicing {
    func sendNotification(title: String, body: String) async
    func sendErrorNotification(error: KuchibiError) async
}
