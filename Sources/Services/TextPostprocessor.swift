import Foundation

/// 認識結果テキストの空白正規化と繰り返し除去を実行する後処理サービス
struct TextPostprocessorImpl: TextPostprocessing {
    func process(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // 1. 先頭・末尾の空白除去
        result = result.trimmingCharacters(in: .whitespaces)

        // 2. 連続スペースを1つに正規化
        result = result.replacing(/\s{2,}/, with: " ")

        // 2.5. 日本語フィラー（言い淀み・つなぎ言葉）を除去
        // 明確なフィラー（長音・促音を含む）は位置を問わず除去
        result = result.replacing(
            /(?:えーと|えっと|うーん|あー+|えー+|うー+|んー+|あ、|ま、)/
        ) { _ in "" }
        // 曖昧なフィラー（通常語と重複しうる）はスペースまたは文境界で囲まれた場合のみ除去
        result = result.replacing(
            /(?:^|\s)(?:まあ|なんか|あの|その)(?=\s|$)/
        ) { _ in "" }
        result = result.trimmingCharacters(in: .whitespaces)

        // 3. 日本語文字間のスペースを除去
        // 日本語文字: ひらがな、カタカナ、漢字、全角句読点・記号
        // 先読み(lookahead)により後続文字を消費せず、連続するスペースをすべて除去する
        result = result.replacing(
            /([\p{Hiragana}\p{Katakana}\p{Han}\u{3000}-\u{303F}\u{FF00}-\u{FFEF}])\s+(?=[\p{Hiragana}\p{Katakana}\p{Han}\u{3000}-\u{303F}\u{FF00}-\u{FFEF}])/
        ) { match in
            "\(match.output.1)"
        }

        // 4. 3文字以上の繰り返しフレーズを1つに集約
        result = result.replacing(/(.{3,}?)\1+/) { match in
            String(match.output.1)
        }

        return result
    }
}
