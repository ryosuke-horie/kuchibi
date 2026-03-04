import Foundation
@testable import Kuchibi

final class MockTextPostprocessor: TextPostprocessing {
    var processCalls: [String] = []
    var transformFunction: ((String) -> String)?

    func process(_ text: String) -> String {
        processCalls.append(text)
        return transformFunction?(text) ?? text
    }
}
