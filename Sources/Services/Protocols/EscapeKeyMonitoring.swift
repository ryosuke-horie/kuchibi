/// ESC キーのグローバル監視プロトコル
protocol EscapeKeyMonitoring {
    /// ESC キー監視を開始する
    /// - Parameter onEscape: ESC 検出時に呼び出されるコールバック（呼び出しスレッドは不定）
    func startMonitoring(onEscape: @escaping () -> Void)

    /// ESC キー監視を停止し、モニターを解放する
    func stopMonitoring()
}
