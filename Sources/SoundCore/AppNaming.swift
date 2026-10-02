import Foundation

/// Rules for turning audio processes into the app names people recognize.
public enum AppNaming {
    /// The outermost `.app` bundle an executable lives in, so helpers
    /// (e.g. `Slack.app/Contents/Frameworks/Slack Helper.app/...`) map to the main app.
    public static func outermostAppBundle(inExecutablePath path: String) -> String? {
        var prefix = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            prefix += "/" + component
            if component.lowercased().hasSuffix(".app") { return prefix }
        }
        return nil
    }

    /// Friendly names for system processes that make sound but aren't apps.
    public static func systemDisplayName(forProcessName name: String) -> String? {
        systemNames[name]
    }

    private static let systemNames: [String: String] = [
        "systemsoundserverd": "System sounds",
        "PowerChime": "Charger chime",
        "usernoted": "Notifications",
        "universalaccessd": "Accessibility",
        "heard": "Background Sounds",
        "corespeechd": "Siri & Dictation",
        "loginwindow": "Login window",
        "avconferenced": "FaceTime audio",
        "callservicesd": "Calls",
        "AirPlayXPCHelper": "AirPlay",
        "com.apple.speech.speechsynthesisd": "Text to speech",
    ]

    /// Processes that typically make short, surprising sounds. They're tapped as soon as they
    /// appear (instead of on first output) so even their first sound is captured in full.
    public static let eagerTapProcessNames: Set<String> = [
        "systemsoundserverd", "PowerChime", "usernoted", "NotificationCenter",
    ]

    /// Identity of a lane. Bundle IDs keep helpers and relaunches together; otherwise the
    /// process name keeps repeated runs of a command-line tool together.
    public static func groupKey(bundleID: String?, processName: String) -> String {
        if let bundleID, !bundleID.isEmpty { return "bundle:" + bundleID }
        return "proc:" + processName
    }
}
