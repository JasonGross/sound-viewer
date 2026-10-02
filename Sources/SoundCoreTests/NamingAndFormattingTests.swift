import SoundCore

func namingTests() {
    section("AppNaming")

    test("a helper executable resolves to its outermost .app") {
        let path = "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper"
        expectEqual(AppNaming.outermostAppBundle(inExecutablePath: path), "/Applications/Slack.app")
    }

    test("a plain app executable resolves to its own bundle") {
        let path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        expectEqual(AppNaming.outermostAppBundle(inExecutablePath: path), "/Applications/Google Chrome.app")
    }

    test("a daemon outside any .app has no bundle") {
        expect(AppNaming.outermostAppBundle(inExecutablePath: "/usr/sbin/systemsoundserverd") == nil)
        let xpc = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        expect(AppNaming.outermostAppBundle(inExecutablePath: xpc) == nil)
    }

    test("a directory merely containing '.app' in its name is not a bundle") {
        expect(AppNaming.outermostAppBundle(inExecutablePath: "/opt/my.application/bin/tool") == nil)
    }

    test("system sound daemons get friendly names") {
        expectEqual(AppNaming.systemDisplayName(forProcessName: "systemsoundserverd"), "System sounds")
        expectEqual(AppNaming.systemDisplayName(forProcessName: "PowerChime"), "Charger chime")
    }

    test("unknown processes have no friendly name") {
        expect(AppNaming.systemDisplayName(forProcessName: "afplay") == nil)
    }

    test("system sound daemons are tapped eagerly") {
        expect(AppNaming.eagerTapProcessNames.contains("systemsoundserverd"))
    }

    test("group keys prefer the bundle ID so helpers and relaunches share a lane") {
        expectEqual(AppNaming.groupKey(bundleID: "com.tinyspeck.slackmacgap", processName: "Slack Helper"),
                    "bundle:com.tinyspeck.slackmacgap")
    }

    test("group keys fall back to the process name, so repeated runs of a tool share a lane") {
        expectEqual(AppNaming.groupKey(bundleID: nil, processName: "afplay"), "proc:afplay")
        expectEqual(AppNaming.groupKey(bundleID: "", processName: "afplay"), "proc:afplay")
    }
}

func formattingTests() {
    section("Formatting")

    test("short durations show tenths of a second") {
        expectEqual(Formatting.duration(seconds: 0.05), "0.1 s")
        expectEqual(Formatting.duration(seconds: 0.4), "0.4 s")
        expectEqual(Formatting.duration(seconds: 9.94), "9.9 s")
    }

    test("medium durations show whole seconds") {
        expectEqual(Formatting.duration(seconds: 12.4), "12 s")
    }

    test("long durations show minutes and seconds") {
        expectEqual(Formatting.duration(seconds: 125), "2 m 05 s")
    }

    test("hour-long durations show hours and minutes") {
        expectEqual(Formatting.duration(seconds: 3900), "1 h 05 m")
    }

    test("levels show whole dB with a real minus sign") {
        expectEqual(Formatting.level(LevelMath.linear(fromDecibels: -12.3)), "−12 dB")
        expectEqual(Formatting.level(1.0), "0 dB")
    }

    test("an unknown level says so") {
        expectEqual(Formatting.level(nil), "level unknown")
    }

    test("silence shows as minus infinity") {
        expectEqual(Formatting.level(0), "−∞ dB")
    }

    test("axis ticks are spaced so a window shows roughly 4–10 of them") {
        for span in [30.0, 120, 600, 3600] {
            let step = Formatting.tickInterval(forSpanSeconds: span)
            let ticks = span / step
            expect(ticks >= 4 && ticks <= 10, "span \(span) → step \(step) gives \(ticks) ticks")
        }
    }
}
