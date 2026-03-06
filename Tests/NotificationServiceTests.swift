import Foundation
import Testing
@testable import Kuchibi

@Suite("NotificationService")
struct NotificationServiceTests {
    @Test("sendErrorNotificationがエラー種別ごとに通知内容を生成する")
    func errorNotificationContent() async {
        let service = NotificationServiceImpl()

        // modelLoadFailed
        let (title1, body1) = service.notificationContent(for: .modelLoadFailed(underlying: NSError(domain: "test", code: 1)))
        #expect(title1.contains("モデル"))
        #expect(!body1.isEmpty)

        // microphonePermissionDenied
        let (title2, body2) = service.notificationContent(for: .microphonePermissionDenied)
        #expect(title2.contains("マイク"))
        #expect(body2.contains("設定"))
    }
}
