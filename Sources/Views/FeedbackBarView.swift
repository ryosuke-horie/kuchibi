import Combine
import SwiftUI

/// 音量レベルと認識テキストを表示するバー型インジケーター
struct FeedbackBarView: View {
    @ObservedObject var sessionManager: SessionManagerImpl

    private let barCount = 10
    private let indicatorWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 4) {
            if sessionManager.state == .processing {
                // 文字起こし中アニメーション
                ProcessingWaveView()
                    .frame(width: indicatorWidth)

                Text("文字起こし中...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                // 音量バー
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        AudioLevelBar(
                            level: sessionManager.audioLevel,
                            index: index,
                            totalBars: barCount
                        )
                    }
                }
                .frame(width: indicatorWidth)

                // 認識テキスト
                if !sessionManager.partialText.isEmpty {
                    Text(sessionManager.partialText)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 36)
        .background(.ultraThinMaterial)
    }
}

/// 文字起こし処理中を表すウェーブアニメーション
struct ProcessingWaveView: View {
    @State private var animating = false

    private let barHeights: [(min: CGFloat, max: CGFloat)] = [
        (4, 10), (4, 16), (4, 20), (4, 16), (4, 10)
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3, height: animating ? barHeights[index].max : barHeights[index].min)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.09),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        // View が .processing ブランチから除外されると同時に破棄されるためアニメーションは自然停止する。
        // opacity 切り替え等で View を再利用するパターンに変更した際は、この false 設定が有効になる。
        .onDisappear { animating = false }
    }
}

/// 個々の音量バー
struct AudioLevelBar: View {
    let level: Float
    let index: Int
    let totalBars: Int

    private var barHeight: CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 20
        guard level > 0 else { return baseHeight }

        let factor = 1.0 - abs(Float(index) - Float(totalBars) / 2.0) / Float(totalBars) * 0.5
        let height = CGFloat(level * factor) * maxHeight
        return max(height, baseHeight)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor.opacity(level > 0 ? 0.8 : 0.3))
            .frame(width: 3, height: barHeight)
            .animation(.linear(duration: 0.05), value: level)
    }
}

/// バー型ウィンドウの管理
@MainActor
final class FeedbackBarWindowController {
    private var window: NSWindow?
    private let sessionManager: SessionManagerImpl
    private var cancellable: AnyCancellable?

    init(sessionManager: SessionManagerImpl) {
        self.sessionManager = sessionManager

        cancellable = sessionManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == .recording || state == .processing {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
    }

    func show() {
        guard window == nil else { return }

        let barView = FeedbackBarView(sessionManager: sessionManager)
        let hostingView = NSHostingView(rootView: barView)

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let barHeight: CGFloat = 36

        let window = NSWindow(
            contentRect: NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: barHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.ignoresMouseEvents = true

        window.orderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    /// テスト用: ウィンドウが表示中かどうか
    var isVisible: Bool { window != nil }
}
