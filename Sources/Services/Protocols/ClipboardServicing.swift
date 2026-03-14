/// クリップボード操作のプロトコル
protocol ClipboardServicing {
    func copyToClipboard(text: String)
    func pasteToActiveApp(text: String, restoreClipboard: Bool) async
    func typeText(_ text: String) async
    func runDiagnostics() async -> String
}
