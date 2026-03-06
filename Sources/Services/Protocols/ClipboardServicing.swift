/// クリップボード操作のプロトコル
protocol ClipboardServicing {
    func copyToClipboard(text: String)
    func pasteToActiveApp(text: String, restoreClipboard: Bool) async
}
