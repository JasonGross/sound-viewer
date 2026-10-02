import AppKit
import SwiftUI

@main
struct SoundViewerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Sound Viewer", id: "main") {
            ContentView()
                .environment(appDelegate.monitor)
        }
        .defaultSize(width: 1180, height: 720)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()
        DebugSnapshot.startIfRequested(monitor: monitor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // History lives in memory only, so closing the window ends the session.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
