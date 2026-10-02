import SoundCore

func timelineMathTests() {
    section("TimelineMath.pinnedEnd")

    test("reaching the present returns to live") {
        expect(TimelineMath.pinnedEnd(proposed: 1000, current: 1000, span: 600, historyBins: 72_000) == nil)
        expect(TimelineMath.pinnedEnd(proposed: 1500, current: 1000, span: 600, historyBins: 72_000) == nil)
    }

    test("a point in recorded history is kept") {
        expectEqual(TimelineMath.pinnedEnd(proposed: 800, current: 1000, span: 600, historyBins: 72_000), 800)
    }

    test("can't scroll back before the app started recording") {
        expectEqual(TimelineMath.pinnedEnd(proposed: 10, current: 1000, span: 600, historyBins: 72_000), 599)
    }

    test("with less history than one window, there's nowhere to scroll") {
        expect(TimelineMath.pinnedEnd(proposed: 100, current: 400, span: 600, historyBins: 72_000) == nil)
    }

    test("can't scroll back past the retained hour") {
        let current = 100_000
        expectEqual(TimelineMath.pinnedEnd(proposed: 0, current: current, span: 600, historyBins: 72_000),
                    current - 72_000 + 600)
    }
}
