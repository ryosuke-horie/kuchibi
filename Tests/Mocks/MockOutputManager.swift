@testable import Kuchibi

final class MockOutputManager: OutputManaging {
    var outputCalls: [(text: String, mode: OutputMode)] = []

    func output(text: String, mode: OutputMode) async {
        outputCalls.append((text: text, mode: mode))
    }
}
