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

    @Test("空文字列は出力しない")
    func emptyText() async {
        let mockClipboard = MockClipboardService()
        let manager = OutputManagerImpl(clipboardService: mockClipboard)

        await manager.output(text: "", mode: .clipboard)

        #expect(mockClipboard.copiedTexts.isEmpty)
    }
}
