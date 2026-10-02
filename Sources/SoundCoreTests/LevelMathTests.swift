import SoundCore

func levelMathTests() {
    section("LevelMath")

    test("full-scale amplitude is 0 dBFS") {
        expectClose(LevelMath.decibels(1.0), 0)
    }

    test("half amplitude is about -6 dBFS") {
        expectClose(LevelMath.decibels(0.5), -6.0206, tolerance: 0.01)
    }

    test("silence clamps to the floor instead of -infinity") {
        expectEqual(LevelMath.decibels(0), LevelMath.floorDB)
        expectEqual(LevelMath.decibels(1e-12), LevelMath.floorDB)
    }

    test("linear(fromDecibels:) inverts decibels") {
        expectClose(LevelMath.linear(fromDecibels: -20), 0.1, tolerance: 1e-5)
    }

    test("measure finds the absolute peak and the sum of squares") {
        let samples: [Float] = [0.1, -0.8, 0.3, 0.0]
        let m = samples.withUnsafeBufferPointer { LevelMath.measure($0) }
        expectClose(m.peak, 0.8)
        expectClose(Float(m.sumOfSquares), 0.01 + 0.64 + 0.09, tolerance: 1e-5)
        expectEqual(m.sampleCount, 4)
    }

    test("measure of an empty buffer is zero") {
        let m = [Float]().withUnsafeBufferPointer { LevelMath.measure($0) }
        expectEqual(m.peak, 0)
        expectEqual(m.sampleCount, 0)
    }

    test("RMS of a constant signal equals its magnitude") {
        let m = LevelMath.Measurement(peak: 0.5, sumOfSquares: 0.25 * 100, sampleCount: 100)
        expectClose(m.rms, 0.5)
    }

    test("RMS with no samples is zero") {
        expectEqual(LevelMath.Measurement.zero.rms, 0)
    }

    test("measurements merge by max peak and summed energy") {
        var a = LevelMath.Measurement(peak: 0.2, sumOfSquares: 1, sampleCount: 10)
        a.merge(LevelMath.Measurement(peak: 0.9, sumOfSquares: 2, sampleCount: 5))
        expectClose(a.peak, 0.9)
        expectClose(Float(a.sumOfSquares), 3)
        expectEqual(a.sampleCount, 15)
    }

    test("displayHeight maps -60…0 dBFS onto 0…1") {
        expectClose(LevelMath.displayHeight(linear: 1.0), 1)
        expectClose(LevelMath.displayHeight(linear: LevelMath.linear(fromDecibels: -30)), 0.5)
        expectEqual(LevelMath.displayHeight(linear: LevelMath.linear(fromDecibels: -70)), 0)
        expectEqual(LevelMath.displayHeight(linear: 0), 0)
    }

    test("displayHeight clamps overs to 1") {
        expectEqual(LevelMath.displayHeight(linear: 2.0), 1)
    }
}
