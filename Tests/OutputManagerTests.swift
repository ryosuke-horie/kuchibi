import Foundation
import Testing
@testable import Kuchibi

@Suite("OutputManager")
struct OutputManagerTests {
    @Test("clipboardモードでClipboardServiceのcopyToClipboardが呼ばれる")
    func clipboardMode() async {
        let mockClipboard = MockClipboardService()
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "テスト", mode: .clipboard)

        #expect(mockClipboard.copiedTexts == ["テスト"])
        #expect(mockClipboard.pastedTexts.isEmpty)
    }

    @Test("directInputモードでClipboardServiceのpasteToActiveAppが呼ばれる")
    func directInputMode() async {
        let mockClipboard = MockClipboardService()
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "直接入力", mode: .directInput)

        #expect(mockClipboard.pastedTexts == ["直接入力"])
        #expect(mockClipboard.copiedTexts.isEmpty)
    }

    @Test("autoInputモードでClipboardServiceのtypeTextが呼ばれる")
    func autoInputMode() async {
        let mockClipboard = MockClipboardService()
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "自動入力テスト", mode: .autoInput)

        #expect(mockClipboard.typedTexts == ["自動入力テスト"])
        #expect(mockClipboard.copiedTexts.isEmpty)
        #expect(mockClipboard.pastedTexts.isEmpty)
    }

    @Test("autoInputモードでtypeText失敗時にpasteToActiveAppにフォールバックする")
    func autoInputFallback() async {
        let mockClipboard = MockClipboardService()
        mockClipboard.shouldFailTypeText = true
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "フォールバック", mode: .autoInput)

        #expect(mockClipboard.typedTexts.isEmpty)
        #expect(mockClipboard.pastedTexts == ["フォールバック"])
    }

    @Test("空文字列は出力しない")
    func emptyText() async {
        let mockClipboard = MockClipboardService()
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "", mode: .clipboard)

        #expect(mockClipboard.copiedTexts.isEmpty)
    }
}
