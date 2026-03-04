/// セッションモニタリングのプロトコル
protocol SessionMonitoring {
    func sessionStarted()
    func textCompleted(text: String)
    func sessionEnded()
    func sessionFailed(error: KuchibiError)
}
