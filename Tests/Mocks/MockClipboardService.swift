@testable import Kuchibi

final class MockClipboardService: ClipboardServicing {
    var copiedTexts: [String] = []
    var pastedTexts: [String] = []
    var typedTexts: [String] = []
    var shouldFailTypeText = false

    func copyToClipboard(text: String) {
        copiedTexts.append(text)
    }

    func pasteToActiveApp(text: String) async {
        pastedTexts.append(text)
    }

    func typeText(_ text: String) async {
        if shouldFailTypeText {
            await pasteToActiveApp(text: text)
        } else {
            typedTexts.append(text)
        }
    }
}
