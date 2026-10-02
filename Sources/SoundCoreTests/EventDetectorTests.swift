import SoundCore

private let loud = LevelBin(peak: 0.5, rms: 0.3, flags: [.captured, .active])
private let silentStream = LevelBin(peak: 0, rms: 0, flags: [.captured, .active])
private let uncapturedOutput = LevelBin(peak: 0, rms: 0, flags: [.active])
private let nothing = LevelBin.empty

private func db(_ d: Float) -> LevelBin {
    LevelBin(peak: LevelMath.linear(fromDecibels: d), rms: 0, flags: [.captured, .active])
}

func eventDetectorTests() {
    section("EventDetector")

    test("a quiet bin starts nothing") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: nothing)
        expect(d.events.isEmpty)
    }

    test("a loud bin starts an ongoing event") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 5, bin: loud)
        expectEqual(d.events.count, 1)
        expectEqual(d.events[0].laneKey, "a")
        expectEqual(d.events[0].startIndex, 5)
        expectEqual(d.events[0].endIndex, 5)
        expect(d.events[0].isOngoing)
        expectClose(d.events[0].peak ?? -1, 0.5)
    }

    test("the -50 dBFS threshold: -49 dB counts, -51 dB does not") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: db(-51))
        expect(d.events.isEmpty)
        d.feed(laneKey: "a", index: 1, bin: db(-49))
        expectEqual(d.events.count, 1)
    }

    test("sounds separated by a short gap merge into one event") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 1, bin: nothing)
        d.feed(laneKey: "a", index: 2, bin: nothing)
        d.feed(laneKey: "a", index: 3, bin: loud)
        expectEqual(d.events.count, 1)
        expectEqual(d.events[0].endIndex, 3)
    }

    test("a long gap closes the event at its last sounding bin") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 1, bin: loud)
        for i in 2...5 { d.feed(laneKey: "a", index: i, bin: nothing) }
        expectEqual(d.events.count, 1)
        expect(!d.events[0].isOngoing)
        expectEqual(d.events[0].endIndex, 1)
        expectEqual(d.events[0].binCount, 2)
    }

    test("a sound after a closed event starts a new event") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        for i in 1...4 { d.feed(laneKey: "a", index: i, bin: nothing) }
        d.feed(laneKey: "a", index: 5, bin: loud)
        expectEqual(d.events.count, 2)
        expect(d.events[0].id != d.events[1].id)
        expectEqual(d.events[1].startIndex, 5)
    }

    test("an open but silent output stream is not a sound") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        for i in 0..<10 { d.feed(laneKey: "a", index: i, bin: silentStream) }
        expect(d.events.isEmpty)
    }

    test("output that was running but not captured counts, with unknown level") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: uncapturedOutput)
        expectEqual(d.events.count, 1)
        expect(d.events[0].peak == nil)
    }

    test("an uncaptured start followed by captured audio is one event with a known peak") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: uncapturedOutput)
        d.feed(laneKey: "a", index: 1, bin: loud)
        expectEqual(d.events.count, 1)
        expectClose(d.events[0].peak ?? -1, 0.5)
    }

    test("lanes are tracked independently") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "b", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 1, bin: loud)
        expectEqual(d.events.count, 2)
        expectEqual(Set(d.events.map(\.laneKey)), ["a", "b"])
    }

    test("the oldest events are dropped beyond maxEvents") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 0, maxEvents: 2)
        for i in stride(from: 0, to: 6, by: 2) {
            d.feed(laneKey: "a", index: i, bin: loud)
            d.feed(laneKey: "a", index: i + 1, bin: nothing)
        }
        expectEqual(d.events.map(\.startIndex), [2, 4])
    }

    test("prune drops closed events that ended before an index") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 0)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 1, bin: nothing)
        d.feed(laneKey: "a", index: 10, bin: loud)
        d.prune(before: 5)
        expectEqual(d.events.map(\.startIndex), [10])
    }

    test("prune keeps an ongoing event even if it started long ago") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 0)
        for i in 0..<10 { d.feed(laneKey: "a", index: i, bin: loud) }
        d.prune(before: 20)
        expectEqual(d.events.count, 1)
    }

    test("lastSoundIndex reports the latest sounding bin per lane") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        expect(d.lastSoundIndex(laneKey: "a") == nil)
        d.feed(laneKey: "a", index: 4, bin: loud)
        d.feed(laneKey: "a", index: 5, bin: nothing)
        expectEqual(d.lastSoundIndex(laneKey: "a"), 4)
    }
}

func eventDetectorGapTests() {
    section("EventDetector gaps")

    test("a sound after an unseen gap (sleep, stalled main thread) starts a new event") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 100, bin: loud)
        expectEqual(d.events.count, 2)
        guard d.events.count == 2 else { return }
        expect(!d.events[0].isOngoing)
        expectEqual(d.events[0].endIndex, 0)
        expectEqual(d.events[1].startIndex, 100)
    }

    test("an unseen gap within the merge window still merges") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3)
        d.feed(laneKey: "a", index: 0, bin: loud)
        d.feed(laneKey: "a", index: 4, bin: loud)
        expectEqual(d.events.count, 1)
        expectEqual(d.events[0].endIndex, 4)
    }

    test("event IDs can start from an offset so two detectors never collide") {
        let d = EventDetector(thresholdDB: -50, mergeGapBins: 3, firstID: 1_000)
        d.feed(laneKey: "a", index: 0, bin: loud)
        expectEqual(d.events[0].id, 1_000)
    }
}

func attributionTests() {
    section("Attribution")

    func event(_ id: Int, _ lane: String, _ start: Int, _ end: Int, ongoing: Bool = false) -> SoundEvent {
        SoundEvent(id: id, laneKey: lane, startIndex: start, endIndex: end, peak: 0.5, isOngoing: ongoing)
    }

    test("a global sound with no app sound at the same time is unattributed") {
        let result = Attribution.unattributed([event(1, "all", 100, 110)], appEvents: [event(2, "app", 0, 10)], slackBins: 2)
        expectEqual(result.map(\.id), [1])
    }

    test("a global sound overlapping an app's sound is attributed to that app") {
        let result = Attribution.unattributed([event(1, "all", 100, 110)], appEvents: [event(2, "app", 105, 120)], slackBins: 2)
        expect(result.isEmpty)
    }

    test("small timing skew between taps still counts as overlap") {
        let result = Attribution.unattributed([event(1, "all", 100, 110)], appEvents: [event(2, "app", 112, 120)], slackBins: 2)
        expect(result.isEmpty)
    }

    test("ongoing global sounds wait until they finish") {
        let result = Attribution.unattributed([event(1, "all", 100, 110, ongoing: true)], appEvents: [], slackBins: 2)
        expect(result.isEmpty)
    }
}
