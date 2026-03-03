/// テキスト出力管理のプロトコル
protocol OutputManaging {
    func output(text: String, mode: OutputMode) async
}
