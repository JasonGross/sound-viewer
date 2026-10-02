import os

/// Unified logging. Watch with:
///   log stream --predicate 'subsystem == "local.SoundViewer"'
enum Log {
    static let audio = Logger(subsystem: "local.SoundViewer", category: "audio")
    static let events = Logger(subsystem: "local.SoundViewer", category: "events")
}
