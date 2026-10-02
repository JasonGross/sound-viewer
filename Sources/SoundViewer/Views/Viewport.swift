import Observation
import SoundCore

/// Which slice of history the timeline shows, plus hover and highlight state shared by all lanes.
@MainActor
@Observable
final class Viewport {
    static let spans: [(label: String, seconds: Double)] = [("30 s", 30), ("2 m", 120), ("10 m", 600), ("60 m", 3600)]

    var spanSeconds: Double = 30
    /// End of the visible range when scrolled back; nil follows live.
    private(set) var pinnedEnd: Int?
    /// Bin under the pointer, shared so every lane draws the same crosshair.
    var hoverIndex: Int?
    /// Event picked in the list; drawn highlighted in its lane.
    private(set) var highlightID: SoundEvent.ID?
    /// Lane of the highlighted event, so the timeline can scroll it into view.
    private(set) var highlightLaneKey: String?
    /// Width of the waveform area in points, for converting gestures to bins.
    var waveformWidth: Double = 600
    /// Bumps on every jump to an event, even the same one again, so the timeline can scroll
    /// that event's lane into view each time.
    private(set) var jumpCount = 0
    /// Sub-bin part of scroll deltas, carried over so slow two-finger scrolls still move.
    private var panRemainder = 0.0

    var spanBins: Int { Int(spanSeconds / BinClock.binSeconds) }
    var isLive: Bool { pinnedEnd == nil }

    func range(current: Int) -> Range<Int> {
        let end = min(pinnedEnd ?? current, current) + 1
        return (end - spanBins)..<end
    }

    /// Pans by a number of bins (negative goes back in time).
    func pan(byBins delta: Int, current: Int) {
        let end = min(pinnedEnd ?? current, current) + delta
        setEnd(end, current: current)
    }

    func pan(byPoints dx: Double, current: Int) {
        let exact = -dx * Double(spanBins) / max(1, waveformWidth) + panRemainder
        let bins = Int(exact.rounded(.towardZero))
        panRemainder = exact - Double(bins)
        if bins != 0 { pan(byBins: bins, current: current) }
    }

    func setEnd(_ end: Int, current: Int) {
        pinnedEnd = TimelineMath.pinnedEnd(proposed: end, current: current, span: spanBins,
                                           historyBins: BinClock.historyBins)
    }

    func show(_ event: SoundEvent, current: Int) {
        highlightID = event.id
        highlightLaneKey = event.laneKey
        jumpCount += 1
        if event.isOngoing {
            pinnedEnd = nil
        } else if event.binCount >= spanBins * 9 / 10 {
            setEnd(event.startIndex + spanBins * 9 / 10, current: current)  // too long to fit: show its start
        } else {
            setEnd((event.startIndex + event.endIndex) / 2 + spanBins / 2, current: current)
        }
    }

    func goLive() {
        pinnedEnd = nil
        highlightID = nil
        highlightLaneKey = nil
    }
}
