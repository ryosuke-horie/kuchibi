import Foundation
import Testing
@testable import Kuchibi

@Suite("TextPostprocessor")
struct TextPostprocessorTests {
    let processor = TextPostprocessorImpl()

    // MARK: - 空白正規化テスト

    @Test("先頭と末尾の空白が除去される")
    func trimsLeadingAndTrailingWhitespace() {
        #expect(processor.process("  こんにちは  ") == "こんにちは")
    }

    @Test("日本語文字間のスペースが除去される")
    func removesSpacesBetweenJapaneseChars() {
        #expect(processor.process("こんにちは 世界") == "こんにちは世界")
    }

    @Test("漢字間のスペースが除去される")
    func removesSpacesBetweenKanji() {
        #expect(processor.process("音声 認識 結果") == "音声認識結果")
    }

    @Test("カタカナ間のスペースが除去される")
    func removesSpacesBetweenKatakana() {
        #expect(processor.process("テキスト ポスト プロセッサ") == "テキストポストプロセッサ")
    }

    @Test("ひらがなと漢字間のスペースが除去される")
    func removesSpacesBetweenHiraganaAndKanji() {
        #expect(processor.process("お 元気 です か") == "お元気ですか")
    }

    @Test("各文字間にスペースがある日本語テキストのスペースがすべて除去される")
    func removesAllSpacesBetweenEveryJapaneseChar() {
        #expect(processor.process("こ れ か ら 動 作 確 認") == "これから動作確認")
    }

    @Test("英数字と日本語文字の間のスペースは保持される")
    func preservesSpacesBetweenAlphanumAndJapanese() {
        #expect(processor.process("Hello こんにちは") == "Hello こんにちは")
        #expect(processor.process("バージョン 2.0 です") == "バージョン 2.0 です")
    }

    @Test("英単語間のスペースは保持される")
    func preservesSpacesBetweenEnglishWords() {
        #expect(processor.process("Hello World") == "Hello World")
    }

    @Test("連続する半角スペースが1つに正規化される")
    func normalizesConsecutiveSpaces() {
        #expect(processor.process("Hello   World") == "Hello World")
    }

    @Test("空文字列はそのまま返す")
    func returnsEmptyStringUnchanged() {
        #expect(processor.process("") == "")
    }

    // MARK: - 繰り返し除去テスト

    @Test("3文字以上の繰り返しが除去される")
    func removesRepeatedPhrases() {
        #expect(processor.process("こんにちはこんにちは") == "こんにちは")
    }

    @Test("3回以上の繰り返しも1つに集約される")
    func removesTripleRepeatedPhrases() {
        #expect(processor.process("ありがとうありがとうありがとう") == "ありがとう")
    }

    @Test("2文字以下の繰り返しは保持される")
    func preservesShortRepeats() {
        #expect(processor.process("はは") == "はは")
        #expect(processor.process("のの") == "のの")
    }

    @Test("混合テキストで正しく処理される")
    func processesComplexText() {
        let input = "  音声 認識 ありがとうありがとう  "
        let expected = "音声認識ありがとう"
        #expect(processor.process(input) == expected)
    }
}
