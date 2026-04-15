import Foundation

/// Whisper 系モデル（WhisperKit / whisper.cpp）の典型的な hallucination を検出・除去するユーティリティ。
///
/// 無音やノイズに対して decoder が `aaaaa` / `あああああ` / `。。。。` のような低多様性の繰り返し
/// トークンを暴走出力する問題（Whisper 共通の既知事象）を、上位層へ流さないようフィルタする。
/// 両 adapter から共通に呼ばれる。
enum HallucinationFilter {
    /// hallucination と判定した場合は空文字、それ以外は trim 済みテキストを返す。
    static func filter(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }

        // 1. 連続同一文字パターン（`aaaaaaaaaaaaaa` / `あああああああ`）
        var prev: Character? = nil
        var currentRun = 1
        var maxRun = 1
        for ch in trimmed {
            if ch == prev {
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 1
                prev = ch
            }
        }
        if maxRun >= 5 && Float(maxRun) / Float(trimmed.count) > 0.6 {
            return ""
        }

        // 2. 文字多様性: 非空白・非句読点を見て文字種が極端に少ないなら hallucination
        //    例: `a a a a a a a a` / `あ あ あ あ あ あ` のように空白で区切られたパターンも拾う
        let meaningfulChars = trimmed.filter { !$0.isWhitespace && !$0.isPunctuation }
        if meaningfulChars.count >= 5 {
            let uniqueChars = Set(meaningfulChars)
            if uniqueChars.count <= 2 {
                return ""
            }
        }

        return trimmed
    }
}
