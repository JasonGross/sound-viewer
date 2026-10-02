import AppKit

/// Development aid: launched with `SOUNDVIEWER_SNAPSHOT=/path/to/file.png`, the app writes a PNG
/// of its own window there every 2 seconds. Apps can always draw their own windows, so this
/// needs no screen-recording permission:
///   open --env SOUNDVIEWER_SNAPSHOT=/tmp/sv.png "build/Sound Viewer.app"
@MainActor
enum DebugSnapshot {
    private static var timer: Timer?

    static func startIfRequested(monitor: Monitor) {
        guard let path = ProcessInfo.processInfo.environment["SOUNDVIEWER_SNAPSHOT"], !path.isEmpty else { return }
        monitor.publishWhileHidden = true
        let url = URL(fileURLWithPath: path)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { write(to: url) }
        }
    }

    private static func write(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
    }
}
