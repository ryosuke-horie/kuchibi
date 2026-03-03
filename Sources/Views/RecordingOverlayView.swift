import SwiftUI

/// 録音中に表示されるフローティングオーバーレイ
struct RecordingOverlayView: View {
    @ObservedObject var sessionManager: SessionManagerImpl

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseOpacity)

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
    }

    private var pulseOpacity: Double {
        sessionManager.state == .recording ? 1.0 : 0.3
    }
}

/// オーバーレイウィンドウの管理
final class OverlayWindowController {
    private var window: NSWindow?
    private let sessionManager: SessionManagerImpl

    init(sessionManager: SessionManagerImpl) {
        self.sessionManager = sessionManager
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
