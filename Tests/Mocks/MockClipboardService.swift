@testable import Kuchibi

final class MockClipboardService: ClipboardServicing {
    var copiedTexts: [String] = []
    var pastedTexts: [String] = []
    var lastRestoreClipboard: Bool? = nil

    func copyToClipboard(text: String) {
        copiedTexts.append(text)
    }

    func pasteToActiveApp(text: String, restoreClipboard: Bool) async {
        pastedTexts.append(text)
        lastRestoreClipboard = restoreClipboard
    }
}
