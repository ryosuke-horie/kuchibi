@testable import Kuchibi

final class MockClipboardService: ClipboardServicing {
    var copiedTexts: [String] = []
    var pastedTexts: [String] = []

    func copyToClipboard(text: String) {
        copiedTexts.append(text)
    }

    func pasteToActiveApp(text: String) async {
        pastedTexts.append(text)
    }
}
