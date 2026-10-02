import Foundation

/// A stretch of time during which one lane was making sound.
public struct SoundEvent: Identifiable, Equatable, Sendable {
    public let id: Int
    public let laneKey: String
    public var startIndex: Int
    /// Last sounding bin (inclusive).
    public var endIndex: Int
    /// Loudest captured level (linear), or nil if output was detected but never captured.
    public var peak: Float?
    public var isOngoing: Bool

    public var binCount: Int { endIndex - startIndex + 1 }

    public init(id: Int, laneKey: String, startIndex: Int, endIndex: Int, peak: Float?, isOngoing: Bool) {
        self.id = id
        self.laneKey = laneKey
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.peak = peak
        self.isOngoing = isOngoing
    }
}

/// Turns each lane's stream of bins into discrete sound events.
///
/// A bin is *sounding* when a tap captured it above the threshold, or when the app had
/// output running but no tap captured it (we know it played, just not how loudly).
/// Sounding bins separated by at most `mergeGapBins` quiet bins belong to one event.
public final class EventDetector {
    public let thresholdLinear: Float
    public let mergeGapBins: Int
    public let maxEvents: Int
    /// Oldest first.
    public private(set) var events: [SoundEvent] = []

    private var openEventID: [String: Int] = [:]
    private var lastSound: [String: Int] = [:]
    private var nextID: Int

    /// `firstID` lets two detectors hand out IDs that never collide.
    public init(thresholdDB: Float = -50, mergeGapBins: Int = 20, maxEvents: Int = 1000, firstID: Int = 0) {
        thresholdLinear = LevelMath.linear(fromDecibels: thresholdDB)
        self.mergeGapBins = mergeGapBins
        self.maxEvents = maxEvents
        nextID = firstID
    }

    public func isSounding(_ bin: LevelBin) -> Bool {
        bin.flags.contains(.captured) ? bin.peak >= thresholdLinear : bin.flags.contains(.active)
    }

    public func lastSoundIndex(laneKey: String) -> Int? { lastSound[laneKey] }

    public func feed(laneKey: String, index: Int, bin: LevelBin) {
        var pos = openEventID[laneKey].flatMap { id in events.lastIndex { $0.id == id } }

        // Bins we never saw (sleep, a stalled tick) count as silence, so a long enough gap
        // ends the event even though no quiet bin arrived to close it.
        if let p = pos, index - events[p].endIndex - 1 > mergeGapBins {
            events[p].isOngoing = false
            openEventID[laneKey] = nil
            pos = nil
        }

        guard isSounding(bin) else {
            if let pos, index - events[pos].endIndex > mergeGapBins {
                events[pos].isOngoing = false
                openEventID[laneKey] = nil
            }
            return
        }

        lastSound[laneKey] = index
        let capturedPeak: Float? = bin.flags.contains(.captured) ? bin.peak : nil

        if let pos {
            events[pos].endIndex = index
            if let p = capturedPeak { events[pos].peak = max(events[pos].peak ?? 0, p) }
        } else {
            let event = SoundEvent(id: nextID, laneKey: laneKey, startIndex: index, endIndex: index,
                                   peak: capturedPeak, isOngoing: true)
            nextID += 1
            events.append(event)
            openEventID[laneKey] = event.id
            if events.count > maxEvents { dropOldest(events.count - maxEvents) }
        }
    }

    /// Drops finished events that ended before `index` (e.g. older than the history window).
    public func prune(before index: Int) {
        events.removeAll { !$0.isOngoing && $0.endIndex < index }
    }

    public func removeAll() {
        events.removeAll()
        openEventID.removeAll()
    }

    private func dropOldest(_ n: Int) {
        let dropped = events.prefix(n)
        for e in dropped where openEventID[e.laneKey] == e.id { openEventID[e.laneKey] = nil }
        events.removeFirst(n)
    }
}
