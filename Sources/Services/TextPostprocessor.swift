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

        // 3. 日本語文字間のスペースを除去
        // 日本語文字: ひらがな、カタカナ、漢字、全角句読点・記号
        result = result.replacing(
            /([\p{Hiragana}\p{Katakana}\p{Han}\u{3000}-\u{303F}\u{FF00}-\u{FFEF}])\s+([\p{Hiragana}\p{Katakana}\p{Han}\u{3000}-\u{303F}\u{FF00}-\u{FFEF}])/
        ) { match in
            "\(match.output.1)\(match.output.2)"
        }

        // 4. 3文字以上の繰り返しフレーズを1つに集約
        result = result.replacing(/(.{3,}?)\1+/) { match in
            String(match.output.1)
        }

        return result
    }
}
