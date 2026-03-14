@testable import Kuchibi

final class MockClipboardService: ClipboardServicing {
    var copiedTexts: [String] = []
    var pastedTexts: [String] = []
    var typedTexts: [String] = []
    var lastRestoreClipboard: Bool? = nil

    func copyToClipboard(text: String) {
        copiedTexts.append(text)
    }

    func pasteToActiveApp(text: String, restoreClipboard: Bool) async {
        pastedTexts.append(text)
        lastRestoreClipboard = restoreClipboard
    }

    func typeText(_ text: String) async {
        typedTexts.append(text)
    }

    func runDiagnostics() async -> String {
        return "mock diagnostics"
    }
}
