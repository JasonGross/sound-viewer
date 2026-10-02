import Foundation

/// Text for durations, levels and time-axis spacing.
public enum Formatting {
    public static func duration(seconds: Double) -> String {
        let tenths = max(1, Int((seconds * 10).rounded()))
        if tenths < 100 { return "\(tenths / 10).\(tenths % 10) s" }
        if seconds < 59.5 { return "\(Int(seconds.rounded())) s" }
        let total = Int(seconds.rounded())
        if total < 3600 { return "\(total / 60) m " + String(format: "%02d", total % 60) + " s" }
        return "\(total / 3600) h " + String(format: "%02d", (total % 3600) / 60) + " m"
    }

    /// A linear level as whole dBFS, or "level unknown" when nothing was captured.
    public static func level(_ linear: Float?) -> String {
        guard let linear else { return "level unknown" }
        let db = LevelMath.decibels(linear)
        if db <= LevelMath.floorDB { return "−∞ dB" }
        let rounded = Int(db.rounded())
        return rounded < 0 ? "−\(-rounded) dB" : "\(rounded) dB"
    }

    /// Seconds between labeled ticks so a window of `span` seconds gets at most 8 of them.
    public static func tickInterval(forSpanSeconds span: Double) -> Double {
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        return steps.first { span / $0 <= 8 } ?? steps.last!
    }
}
