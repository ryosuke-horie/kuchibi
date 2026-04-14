@testable import Kuchibi

/// `LaunchPathValidating` のテスト用モック。
final class MockLaunchPathValidator: LaunchPathValidating {
    var isApproved: Bool
    var currentPath: String

    init(isApproved: Bool = true, currentPath: String = "/Applications/Kuchibi.app") {
        self.isApproved = isApproved
        self.currentPath = currentPath
    }
}
