import SoundCore

private func bin(_ peak: Float, rms: Float = 0, _ flags: BinFlags = [.captured]) -> LevelBin {
    LevelBin(peak: peak, rms: rms, flags: flags)
}

func levelHistoryTests() {
    section("LevelHistory")

    test("a new history is empty") {
        let h = LevelHistory(capacity: 8)
        expectEqual(h.latestIndex, -1)
        expectEqual(h[0], .empty)
    }

    test("reads back what was written") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.5), at: 0)
        h.write(bin(0.25), at: 1)
        expectEqual(h[0], bin(0.5))
        expectEqual(h[1], bin(0.25))
        expectEqual(h.latestIndex, 1)
    }

    test("indexes past the latest write are empty") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.5), at: 0)
        expectEqual(h[1], .empty)
        expectEqual(h[-1], .empty)
    }

    test("skipped indexes read as empty") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.5), at: 0)
        h.write(bin(0.7), at: 3)
        expectEqual(h[1], .empty)
        expectEqual(h[2], .empty)
        expectEqual(h[3], bin(0.7))
    }

    test("old bins fall off once capacity is exceeded") {
        let h = LevelHistory(capacity: 4)
        for i in 0..<6 { h.write(bin(Float(i) / 10), at: i) }
        expectEqual(h[0], .empty)
        expectEqual(h[1], .empty)
        expectEqual(h[2], bin(0.2))
        expectEqual(h[5], bin(0.5))
        expectEqual(h.oldestIndex, 2)
    }

    test("a gap longer than capacity leaves no stale data behind") {
        let h = LevelHistory(capacity: 4)
        h.write(bin(0.9), at: 0)
        h.write(bin(0.9), at: 1)
        h.write(bin(0.3), at: 10)
        for i in 7...9 { expectEqual(h[i], .empty) }
        expectEqual(h[10], bin(0.3))
    }

    test("a history that starts late is empty before its first write") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.4), at: 100)
        expectEqual(h[99], .empty)
        expectEqual(h[100], bin(0.4))
    }

    test("rewriting the latest index replaces it") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.4), at: 2)
        h.write(bin(0.6), at: 2)
        expectEqual(h[2], bin(0.6))
    }

    test("columns reduce bins by max level and union of flags") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.1, rms: 0.05, [.active]), at: 0)
        h.write(bin(0.4, rms: 0.2, [.captured]), at: 1)
        h.write(bin(0.3, rms: 0.3, [.captured]), at: 2)
        h.write(bin(0.2, rms: 0.1, [.captured]), at: 3)
        let cols = h.columns(from: 0, to: 4, count: 2)
        expectEqual(cols.count, 2)
        expectEqual(cols[0], bin(0.4, rms: 0.2, [.active, .captured]))
        expectEqual(cols[1], bin(0.3, rms: 0.3, [.captured]))
    }

    test("columns repeat bins when zoomed in past one bin per column") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.1), at: 0)
        h.write(bin(0.2), at: 1)
        let cols = h.columns(from: 0, to: 2, count: 4)
        expectEqual(cols.map(\.peak), [0.1, 0.1, 0.2, 0.2])
    }

    test("columns outside recorded history are empty") {
        let h = LevelHistory(capacity: 8)
        h.write(bin(0.5), at: 0)
        let cols = h.columns(from: -4, to: 0, count: 2)
        expectEqual(cols, [.empty, .empty])
    }
}
