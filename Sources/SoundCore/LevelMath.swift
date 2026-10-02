import Foundation

/// Level arithmetic shared by the audio thread (measuring buffers) and the UI (drawing them).
/// Levels are linear amplitudes (1.0 = full scale) unless a name says dB.
public enum LevelMath {
    /// Anything quieter than this is reported as this, so silence never becomes -infinity.
    public static let floorDB: Float = -100
    /// The waveform's vertical scale spans this many dB below full scale.
    public static let displayRangeDB: Float = 60

    public static func decibels(_ linear: Float) -> Float {
        guard linear > 0 else { return floorDB }
        return max(floorDB, 20 * log10(linear))
    }

    public static func linear(fromDecibels db: Float) -> Float {
        powf(10, db / 20)
    }

    /// Height (0…1) for drawing a level, on a dB scale so quiet sounds stay visible.
    public static func displayHeight(linear: Float) -> Float {
        let db = decibels(linear)
        return min(1, max(0, (db + displayRangeDB) / displayRangeDB))
    }

    /// Peak and energy of a run of samples. Safe to call on the real-time audio thread.
    public struct Measurement: Equatable, Sendable {
        public var peak: Float
        public var sumOfSquares: Double
        public var sampleCount: Int

        public static let zero = Measurement(peak: 0, sumOfSquares: 0, sampleCount: 0)

        public init(peak: Float, sumOfSquares: Double, sampleCount: Int) {
            self.peak = peak
            self.sumOfSquares = sumOfSquares
            self.sampleCount = sampleCount
        }

        public var rms: Float {
            sampleCount > 0 ? Float((sumOfSquares / Double(sampleCount)).squareRoot()) : 0
        }

        public mutating func merge(_ other: Measurement) {
            peak = max(peak, other.peak)
            sumOfSquares += other.sumOfSquares
            sampleCount += other.sampleCount
        }
    }

    public static func measure(_ samples: UnsafeBufferPointer<Float>) -> Measurement {
        var peak: Float = 0
        var sum: Float = 0
        for s in samples {
            peak = max(peak, abs(s))
            sum += s * s
        }
        return Measurement(peak: peak, sumOfSquares: Double(sum), sampleCount: samples.count)
    }
}
