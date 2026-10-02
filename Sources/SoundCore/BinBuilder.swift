import Foundation

/// Combines what each of a lane's processes did during one bin into that lane's bin.
public enum BinBuilder {
    public struct ProcessSample: Sendable {
        /// Everything the process's tap delivered during the bin (zero if it delivered nothing).
        public var measurement: LevelMath.Measurement
        /// The process had an output stream running at some point during the bin.
        public var outputRan: Bool

        public init(measurement: LevelMath.Measurement, outputRan: Bool) {
            self.measurement = measurement
            self.outputRan = outputRan
        }
    }

    /// Whether a process's output should mark its bin `.active`.
    ///
    /// Running output without captured audio means "we know it played, not how loudly",
    /// which the event detector treats as a sound. That's right when output *just started*
    /// (its tap needs ~100 ms to begin delivering) or when we can't capture at all, but wrong
    /// for a stream that was already open while taps are (re)starting, e.g. at launch.
    public static func outputCounts(running: Bool, captured: Bool, justStarted: Bool, levelsTrusted: Bool) -> Bool {
        running && (captured || justStarted || !levelsTrusted)
    }

    /// `levelsTrusted` is false when audio-capture permission is missing: taps then deliver
    /// pure silence, which must not be mistaken for "captured and quiet".
    public static func bin(from samples: [ProcessSample], levelsTrusted: Bool) -> LevelBin {
        var out = LevelBin.empty
        for s in samples {
            var b = LevelBin.empty
            if s.outputRan { b.flags.insert(.active) }
            if levelsTrusted, s.measurement.sampleCount > 0 {
                b.peak = s.measurement.peak
                b.rms = s.measurement.rms
                b.flags.insert(.captured)
            }
            out.absorb(b)
        }
        return out
    }
}

/// Maps monotonic time (seconds) onto bin indexes.
public struct BinClock: Sendable {
    public static let binSeconds: Double = 0.05
    public static let historyBins = Int((60 * 60) / binSeconds)

    public let start: Double

    public init(start: Double) { self.start = start }

    public func index(at time: Double) -> Int {
        // The epsilon keeps exact bin boundaries from flooring down through float error.
        Int(((time - start) / Self.binSeconds + 1e-6).rounded(.down))
    }

    public func time(ofIndex index: Int) -> Double {
        start + Double(index) * Self.binSeconds
    }
}
