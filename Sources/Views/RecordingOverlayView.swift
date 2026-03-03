import Combine
import SwiftUI

/// 録音中に表示されるフローティングオーバーレイ
struct RecordingOverlayView: View {
    @ObservedObject var sessionManager: SessionManagerImpl
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(isPulsing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                Text("録音中...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if !sessionManager.partialText.isEmpty {
                Text(sessionManager.partialText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            isPulsing = true
        }
    }
}

/// オーバーレイウィンドウの管理
@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let sessionManager: SessionManagerImpl
    private var cancellable: AnyCancellable?

    init(sessionManager: SessionManagerImpl) {
        self.sessionManager = sessionManager

        // セッション状態を監視してオーバーレイの表示/非表示を制御
        cancellable = sessionManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == .recording {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
    }

    func show() {
        guard window == nil else { return }

        let overlayView = RecordingOverlayView(sessionManager: sessionManager)
        let hostingView = NSHostingView(rootView: overlayView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false

        // 画面中央上部に配置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 150
            let y = screenFrame.maxY - 100
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
