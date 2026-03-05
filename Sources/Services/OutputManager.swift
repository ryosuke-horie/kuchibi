import os

/// テキスト出力モード管理
final class OutputManagerImpl: OutputManaging {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "OutputManager")

    private let clipboardService: ClipboardServicing

    init(clipboardService: ClipboardServicing) {
        self.clipboardService = clipboardService
    }

    func output(text: String, mode: OutputMode) async {
        guard !text.isEmpty else { return }

        switch mode {
        case .clipboard:
            clipboardService.copyToClipboard(text: text)
            Self.logger.info("クリップボードにコピー完了")
        case .directInput:
            await clipboardService.pasteToActiveApp(text: text)
            Self.logger.info("直接入力完了")
        case .autoInput:
            await clipboardService.typeText(text)
            Self.logger.info("自動入力完了")
        }
    }
}
