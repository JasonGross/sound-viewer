import Foundation

public enum TimelineMath {
    /// Where to pin the end of a `span`-bin window when the user scrolls to `proposed`,
    /// or nil to follow live. Never lets the window start before the oldest recorded bin.
    public static func pinnedEnd(proposed: Int, current: Int, span: Int, historyBins: Int) -> Int? {
        let oldestRecorded = max(0, current - historyBins + 1)
        let end = max(proposed, oldestRecorded + span - 1)
        return end >= current ? nil : end
    }
}
