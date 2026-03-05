/// クリップボード操作のプロトコル
protocol ClipboardServicing {
    func copyToClipboard(text: String)
    func pasteToActiveApp(text: String) async
    func typeText(_ text: String) async
}
