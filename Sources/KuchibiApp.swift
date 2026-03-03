import SwiftUI

@main
struct KuchibiApp: App {
    var body: some Scene {
        MenuBarExtra("Kuchibi", systemImage: "mic") {
            Text("Kuchibi 音声入力")
            Divider()
            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
