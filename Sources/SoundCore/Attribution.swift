import Foundation

public enum Attribution {
    /// Finished sounds the all-audio tap heard that no app's lane accounts for: e.g. a process
    /// that exited before it could be identified, or one whose tap failed. Listing them as
    /// "Unknown app" means no audible sound goes unlisted. `slackBins` absorbs timing skew
    /// between separate taps.
    public static func unattributed(_ globalEvents: [SoundEvent], appEvents: [SoundEvent], slackBins: Int) -> [SoundEvent] {
        globalEvents.filter { g in
            !g.isOngoing && !appEvents.contains { a in
                a.startIndex <= g.endIndex + slackBins && a.endIndex >= g.startIndex - slackBins
            }
        }
    }
}
