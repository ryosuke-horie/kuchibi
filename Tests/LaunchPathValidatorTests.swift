import Foundation
import Testing
@testable import Kuchibi

@Suite("LaunchPathValidator")
struct LaunchPathValidatorTests {
    @Test("承認パスから起動: isApproved == true、currentPath が一致")
    func approvedPath() {
        let validator = LaunchPathValidator(currentBundlePath: "/Applications/Kuchibi.app")
        #expect(validator.isApproved)
        #expect(validator.currentPath == "/Applications/Kuchibi.app")
    }

    @Test("DerivedData パスから起動: isApproved == false")
    func derivedDataPath() {
        let derivedPath = "/Users/test/Library/Developer/Xcode/DerivedData/Kuchibi-abcd/Build/Products/Debug/Kuchibi.app"
        let validator = LaunchPathValidator(currentBundlePath: derivedPath)
        #expect(!validator.isApproved)
        #expect(validator.currentPath == derivedPath)
    }

    @Test("その他のパス（例: ~/Downloads）から起動: isApproved == false")
    func otherPath() {
        let other = "/Users/test/Downloads/Kuchibi.app"
        let validator = LaunchPathValidator(currentBundlePath: other)
        #expect(!validator.isApproved)
        #expect(validator.currentPath == other)
    }
}
