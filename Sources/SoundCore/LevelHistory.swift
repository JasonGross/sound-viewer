import Foundation

public struct BinFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// A tap delivered audio for this bin, so `peak`/`rms` are real measurements.
    public static let captured = BinFlags(rawValue: 1 << 0)
    /// The app had an output stream running at some point during this bin.
    public static let active = BinFlags(rawValue: 1 << 1)
}

/// One time slot of a lane's history. Levels are linear amplitudes.
public struct LevelBin: Equatable, Sendable {
    public var peak: Float
    public var rms: Float
    public var flags: BinFlags

    public static let empty = LevelBin(peak: 0, rms: 0, flags: [])

    public init(peak: Float, rms: Float, flags: BinFlags) {
        self.peak = peak
        self.rms = rms
        self.flags = flags
    }

    /// Combines two bins the way a zoomed-out waveform wants: loudest wins, flags accumulate.
    public mutating func absorb(_ other: LevelBin) {
        peak = max(peak, other.peak)
        rms = max(rms, other.rms)
        flags.formUnion(other.flags)
    }
}

/// Fixed-capacity ring buffer of bins addressed by an ever-increasing bin index.
/// Indexes that were skipped, never written, or have aged out read as `.empty`.
public final class LevelHistory {
    public let capacity: Int
    public private(set) var latestIndex = -1
    private var firstIndex = Int.max
    private var storage: [LevelBin]

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: .empty, count: capacity)
    }

    /// Oldest index that can still hold data.
    public var oldestIndex: Int { max(firstIndex == .max ? 0 : firstIndex, latestIndex - capacity + 1) }

    public subscript(index: Int) -> LevelBin {
        guard latestIndex >= 0, index <= latestIndex, index >= oldestIndex else { return .empty }
        return storage[slot(index)]
    }

    /// Writes `bin` at `index`. Writing ahead of `latestIndex` clears any skipped slots;
    /// rewriting a retained older index replaces it; writes older than that are ignored.
    public func write(_ bin: LevelBin, at index: Int) {
        if latestIndex < 0 {
            firstIndex = index
            latestIndex = index
        } else if index > latestIndex {
            let skipped = index - latestIndex - 1
            if skipped >= capacity {
                for i in storage.indices { storage[i] = .empty }
            } else if skipped > 0 {
                for i in (latestIndex + 1)..<index { storage[slot(i)] = .empty }
            }
            latestIndex = index
        } else if index < oldestIndex {
            return
        }
        storage[slot(index)] = bin
    }

    /// Reduces bins `from..<to` into `count` columns for drawing.
    public func columns(from: Int, to: Int, count: Int) -> [LevelBin] {
        guard count > 0, to > from else { return [] }
        let span = Double(to - from)
        var out = [LevelBin](repeating: .empty, count: count)
        for c in 0..<count {
            let lo = from + Int((Double(c) * span / Double(count)).rounded(.down))
            let hi = max(lo + 1, from + Int((Double(c + 1) * span / Double(count)).rounded(.down)))
            var acc = LevelBin.empty
            for i in lo..<hi { acc.absorb(self[i]) }
            out[c] = acc
        }
        return out
    }

    private func slot(_ index: Int) -> Int {
        let r = index % capacity
        return r < 0 ? r + capacity : r
    }
}
