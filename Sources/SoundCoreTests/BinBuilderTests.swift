import SoundCore

private func m(_ peak: Float, rms: Float, n: Int = 100) -> LevelMath.Measurement {
    LevelMath.Measurement(peak: peak, sumOfSquares: Double(rms * rms) * Double(n), sampleCount: n)
}

func binBuilderTests() {
    section("BinBuilder")

    test("one captured process becomes a captured bin") {
        let bin = BinBuilder.bin(from: [.init(measurement: m(0.5, rms: 0.2), outputRan: true)], levelsTrusted: true)
        expectClose(bin.peak, 0.5)
        expectClose(bin.rms, 0.2)
        expectEqual(bin.flags, [.captured, .active])
    }

    test("several processes combine by their loudest levels") {
        let bin = BinBuilder.bin(from: [
            .init(measurement: m(0.5, rms: 0.1), outputRan: false),
            .init(measurement: m(0.2, rms: 0.3), outputRan: true),
        ], levelsTrusted: true)
        expectClose(bin.peak, 0.5)
        expectClose(bin.rms, 0.3)
        expectEqual(bin.flags, [.captured, .active])
    }

    test("no audio delivered means not captured") {
        let bin = BinBuilder.bin(from: [.init(measurement: .zero, outputRan: true)], levelsTrusted: true)
        expectEqual(bin.flags, [.active])
    }

    test("without permission, taps deliver silence that must not count as captured") {
        let bin = BinBuilder.bin(from: [.init(measurement: m(0, rms: 0), outputRan: true)], levelsTrusted: false)
        expectEqual(bin.flags, [.active])
        expectEqual(bin.peak, 0)
    }

    test("no processes make an empty bin") {
        expectEqual(BinBuilder.bin(from: [], levelsTrusted: true), .empty)
    }
}

func binClockTests() {
    section("BinClock")

    test("bin index counts 50 ms slots from the start time") {
        let clock = BinClock(start: 100)
        expectEqual(clock.index(at: 100), 0)
        expectEqual(clock.index(at: 100.049), 0)
        expectEqual(clock.index(at: 100.05), 1)
        expectEqual(clock.index(at: 160), 1200)
    }

    test("a bin's start time inverts the index") {
        let clock = BinClock(start: 100)
        expectClose(Float(clock.time(ofIndex: 20)), 101)
    }

    test("one hour of history is 72,000 bins") {
        expectEqual(BinClock.historyBins, 72_000)
    }
}

func outputCountsTests() {
    section("BinBuilder.outputCounts")

    test("captured output counts") {
        expect(BinBuilder.outputCounts(running: true, captured: true, justStarted: false, levelsTrusted: true))
    }

    test("no output never counts") {
        expect(!BinBuilder.outputCounts(running: false, captured: true, justStarted: true, levelsTrusted: true))
        expect(!BinBuilder.outputCounts(running: false, captured: false, justStarted: true, levelsTrusted: false))
    }

    test("output that just started counts before its tap delivers audio") {
        expect(BinBuilder.outputCounts(running: true, captured: false, justStarted: true, levelsTrusted: true))
    }

    test("an already-open stream doesn't count while its tap warms up") {
        expect(!BinBuilder.outputCounts(running: true, captured: false, justStarted: false, levelsTrusted: true))
    }

    test("without permission, any running output counts") {
        expect(BinBuilder.outputCounts(running: true, captured: false, justStarted: false, levelsTrusted: false))
    }
}
