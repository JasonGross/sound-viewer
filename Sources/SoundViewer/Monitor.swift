import AppKit
import CoreAudio
import Observation
import SoundCore

/// One timeline row: everything one app (or, for `allLane`, the whole Mac) has played.
final class Lane: Identifiable {
    let id: String
    let name: String
    let icon: AppIdentity.Icon
    /// Index into the lane color palette; negative for the "All sound" lane.
    let colorIndex: Int
    let history = LevelHistory(capacity: BinClock.historyBins)
    /// Names of the processes that have played through this lane (for tooltips).
    var processNames: [String] = []
    /// Processes in this lane that still exist.
    var liveProcessCount = 0

    init(id: String, name: String, icon: AppIdentity.Icon, colorIndex: Int) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorIndex = colorIndex
    }
}

/// The app's model: watches audio processes, taps them, and turns what they play into
/// per-lane history and a list of sound events. Ticks every 50 ms on the main thread.
@MainActor
@Observable
final class Monitor {
    /// App lanes, most recent sound first.
    private(set) var lanes: [Lane] = []
    let allLane = Lane(id: "all", name: "All sound", icon: .symbol("speaker.wave.3.fill"), colorIndex: -1)
    /// Oldest first. Events with `laneKey == allLane.id` are sounds no app accounts for.
    private(set) var events: [SoundEvent] = []
    /// The newest bin shown; bumps every tick while the window is visible, which drives redraws.
    private(set) var currentIndex = 0
    private(set) var permission: AudioPermission.Status = .notDetermined
    /// "Quiet", "Slack is playing", "3 apps playing". Only changes when the text does, so views
    /// that show it don't redraw every tick.
    private(set) var playingSummary = "Quiet"
    /// Keep redrawing while the window is hidden (used by DebugSnapshot).
    @ObservationIgnored var publishWhileHidden = false

    @ObservationIgnored let clock: BinClock
    @ObservationIgnored private var wallStart: Date
    @ObservationIgnored let detector = EventDetector(thresholdDB: -50, mergeGapBins: 20)
    /// Finds sounds in the all-audio lane, to catch any that no app lane accounts for.
    @ObservationIgnored private let globalDetector = EventDetector(thresholdDB: -50, mergeGapBins: 20, firstID: 1 << 40)
    @ObservationIgnored private var unattributedEvents: [SoundEvent] = []
    @ObservationIgnored private var attributedThroughID = (1 << 40) - 1

    @ObservationIgnored private let watcher = ProcessWatcher()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let taps = TapManager()
    @ObservationIgnored private let globalAccumulator = LevelAccumulator()
    @ObservationIgnored private var globalDelivering = false
    @ObservationIgnored private var processes: [AudioObjectID: TrackedProcess] = [:]
    /// Processes that went away since the last tick; drained one last time.
    @ObservationIgnored private var departed: [TrackedProcess] = []
    @ObservationIgnored private var lanesByKey: [String: Lane] = [:]
    @ObservationIgnored private var lastIndex = -1
    /// Until this bin, uncaptured output never counts as a sound (taps are being rebuilt).
    @ObservationIgnored private var suppressFreshUntil = -1
    @ObservationIgnored private var started = false
    /// True while enumerating the processes that already exist at launch.
    @ObservationIgnored private var enumeratingAtLaunch = false
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// If the tick runs late (e.g. a busy main thread), copy its data into up to this many
    /// skipped bins so the waveform doesn't get gaps. Longer gaps (sleep) stay empty.
    private static let maxBackfillBins = 20
    /// How long after output starts we count it as a sound even before its tap delivers audio.
    private static let freshOutputBins = 20
    /// Ignore uncaptured output for this long after taps are rebuilt.
    private static let rebuildGraceBins = 40
    /// Stop an app's tap IO after this long without output (it restarts on the next output).
    private static let idleStopBins = 200
    /// Tolerance for timing skew between the all-audio tap and app taps.
    private static let attributionSlackBins = 4

    private final class TrackedProcess {
        let objectID: AudioObjectID
        let pid: pid_t
        let identity: AppIdentity
        let accumulator = LevelAccumulator()
        var isRunningOutput: Bool
        var outputRanSinceTick: Bool
        /// Bin at which we saw output start; nil if it was already running when we found it.
        var outputStartIndex: Int?
        /// Last bin with output running; nil if it hasn't played since we found it.
        var lastOutputIndex: Int?
        var tapped = false
        var tapActive = false
        var loggedDelivering = false
        var lane: Lane?

        init(objectID: AudioObjectID, pid: pid_t, identity: AppIdentity, isRunningOutput: Bool) {
            self.objectID = objectID
            self.pid = pid
            self.identity = identity
            self.isRunningOutput = isRunningOutput
            outputRanSinceTick = isRunningOutput
        }
    }

    init() {
        clock = BinClock(start: Self.now())
        wallStart = Date()
    }

    /// Monotonic seconds that keep counting through sleep, so bin times stay aligned with the clock.
    static func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9 }

    func date(ofIndex index: Int) -> Date {
        wallStart.addingTimeInterval(Double(index) * BinClock.binSeconds)
    }

    func lane(forKey key: String) -> Lane? { key == allLane.id ? allLane : lanesByKey[key] }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        // Keep sampling on schedule while the window is in the background (no App Nap)...
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Watching which apps make sound")
        // ...but don't let our running audio IO keep the Mac awake (Core Audio would otherwise
        // hold a sleep assertion for as long as any tap is running).
        var sleepingAllowed: UInt32 = 1
        var sleepAddress = propertyAddress(kAudioHardwarePropertySleepingIsAllowed)
        let status = AudioObjectSetPropertyData(.system, &sleepAddress, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &sleepingAllowed)
        if status != noErr { Log.audio.error("couldn't allow idle sleep: \(fourCharCode(status), privacy: .public)") }

        watcher.onAdded = { [unowned self] in processAdded($0) }
        watcher.onRemoved = { [unowned self] in processRemoved($0) }
        watcher.onOutputActivity = { [unowned self] in outputActivity($0) }
        taps.onRebuild = { [weak self] in
            MainActor.assumeIsolated { self?.tapsRebuilt() }
        }

        taps.tap(TapManager.globalKey, label: "All sound", accumulator: globalAccumulator)
        enumeratingAtLaunch = true
        watcher.start()
        enumeratingAtLaunch = false
        applyPermission(AudioPermission.status(), requestIfUndecided: true)

        schedule(every: BinClock.binSeconds) { [weak self] in self?.tick() }
        // Notice when permission is granted or revoked in System Settings.
        schedule(every: 2) { [weak self] in self?.applyPermission(AudioPermission.status(), requestIfUndecided: false) }

        // Event times are wall-clock start + elapsed time; re-anchor if the wall clock jumps.
        let reanchor: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reanchorWallClock() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reanchor))
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: reanchor))
    }

    func stop() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        watcher.stop()
        taps.shutdown()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    func clearEvents() {
        detector.removeAll()
        globalDetector.removeAll()
        unattributedEvents.removeAll()
        events = []
    }

    /// All taps were torn down and rebuilt: apps restarting their IO mustn't look like new
    /// sounds while no tap is delivering.
    private func tapsRebuilt() {
        suppressFreshUntil = lastIndex + Self.rebuildGraceBins
    }

    private func reanchorWallClock() {
        wallStart = Date().addingTimeInterval(-(Self.now() - clock.start))
    }

    private func schedule(every interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func applyPermission(_ status: AudioPermission.Status, requestIfUndecided: Bool) {
        if status == .notDetermined, requestIfUndecided {
            AudioPermission.request { [weak self] granted in
                MainActor.assumeIsolated {
                    self?.applyPermission(granted ? .authorized : .denied, requestIfUndecided: false)
                }
            }
        }
        guard status != permission else { return }
        Log.audio.info("audio capture permission: \(String(describing: status), privacy: .public)")
        permission = status
        taps.setEnabled(status == .authorized)
    }

    // MARK: Processes

    private func processAdded(_ process: ProcessWatcher.AudioProcess) {
        let identity = resolver.identity(pid: process.pid, bundleID: process.bundleID)
        let tracked = TrackedProcess(objectID: process.objectID, pid: process.pid, identity: identity,
                                     isRunningOutput: process.isRunningOutput)
        if process.isRunningOutput, !enumeratingAtLaunch { tracked.outputStartIndex = lastIndex + 1 }
        processes[process.objectID] = tracked
        if process.isRunningOutput || AppNaming.eagerTapProcessNames.contains(identity.processName) {
            startTap(tracked)
        }
    }

    private func processRemoved(_ process: ProcessWatcher.AudioProcess) {
        guard let tracked = processes.removeValue(forKey: process.objectID) else { return }
        if tracked.tapped { taps.untap(process.objectID) }
        resolver.forget(pid: process.pid)
        departed.append(tracked)
    }

    private func outputActivity(_ process: ProcessWatcher.AudioProcess) {
        guard let tracked = processes[process.objectID] else { return }
        if !tracked.isRunningOutput, process.isRunningOutput { tracked.outputStartIndex = lastIndex + 1 }
        tracked.isRunningOutput = process.isRunningOutput
        tracked.outputRanSinceTick = true
        tracked.lastOutputIndex = lastIndex + 1
        if !tracked.tapped {
            startTap(tracked)
        } else if !tracked.tapActive {
            tracked.tapActive = true
            taps.setActive(tracked.objectID, true)
        }
    }

    private func startTap(_ tracked: TrackedProcess) {
        tracked.tapped = true
        tracked.tapActive = true
        taps.tap(tracked.objectID, label: "\(tracked.identity.name) [\(tracked.identity.processName) \(tracked.pid)]",
                 accumulator: tracked.accumulator)
    }

    private func laneFor(_ identity: AppIdentity) -> Lane {
        if let lane = lanesByKey[identity.key] { return lane }
        let lane = Lane(id: identity.key, name: identity.name, icon: identity.icon, colorIndex: lanesByKey.count)
        lanesByKey[identity.key] = lane
        lanes.append(lane)
        Log.events.info("new lane: \(identity.name, privacy: .public) (\(identity.processName, privacy: .public))")
        return lane
    }

    // MARK: Tick

    private func tick() {
        let index = clock.index(at: Self.now())
        guard index > lastIndex else { return }
        let levelsTrusted = permission == .authorized
        let threshold = detector.thresholdLinear

        // The all-audio tap runs continuously, so it knows whether anything was audible in this
        // bin. If it heard silence, an app whose own tap is still starting wasn't making sound.
        let globalMeasurement = globalAccumulator.drain()
        let globalTrusted = levelsTrusted && globalAccumulator.health != .failed
        let globalHeardSilence = globalTrusted && globalMeasurement.sampleCount > 0 && globalMeasurement.peak < threshold
        let freshCounts = !globalHeardSilence && index > suppressFreshUntil
        if !globalDelivering, globalAccumulator.health == .delivering {
            globalDelivering = true
            Log.audio.info("tap delivering: All sound")
        }

        var samples: [String: [BinBuilder.ProcessSample]] = [:]
        var anyOutput = false
        var liveCounts: [String: Int] = [:]

        func collect(_ tracked: TrackedProcess, live: Bool) {
            var measurement = tracked.accumulator.drain()
            let health = tracked.accumulator.health
            let trusted = levelsTrusted && health != .failed
            if !trusted { measurement = .zero }  // a failed tap's silence isn't a measurement
            if health == .delivering, !tracked.loggedDelivering {
                tracked.loggedDelivering = true
                Log.audio.info("tap delivering: \(tracked.identity.name, privacy: .public) [\(tracked.identity.processName, privacy: .public)]")
            }

            let running = tracked.isRunningOutput || tracked.outputRanSinceTick
            tracked.outputRanSinceTick = false
            if running { tracked.lastOutputIndex = index }
            let justStarted = freshCounts && (tracked.outputStartIndex.map { index - $0 <= Self.freshOutputBins } ?? false)
            let captured = measurement.sampleCount > 0
            let ran = BinBuilder.outputCounts(running: running, captured: captured,
                                              justStarted: justStarted, levelsTrusted: trusted)

            // Lanes appear the first time a process is audible, not merely when it opens a
            // (possibly silent) output stream.
            let sounding = captured ? measurement.peak >= threshold : ran
            if tracked.lane == nil, sounding {
                let lane = laneFor(tracked.identity)
                if !lane.processNames.contains(tracked.identity.processName) {
                    lane.processNames.append(tracked.identity.processName)
                }
                tracked.lane = lane
            }
            anyOutput = anyOutput || running
            guard let lane = tracked.lane else { return }
            if live { liveCounts[lane.id, default: 0] += 1 }
            samples[lane.id, default: []].append(.init(measurement: measurement, outputRan: ran))
        }
        for tracked in processes.values { collect(tracked, live: true) }
        for tracked in departed { collect(tracked, live: false) }
        departed.removeAll()

        let first = lastIndex < 0 ? index : max(lastIndex + 1, index - Self.maxBackfillBins)
        for lane in lanes {
            lane.liveProcessCount = liveCounts[lane.id] ?? 0
            let bin = BinBuilder.bin(from: samples[lane.id] ?? [], levelsTrusted: levelsTrusted)
            for i in first...index {
                lane.history.write(bin, at: i)
                detector.feed(laneKey: lane.id, index: i, bin: bin)
            }
        }
        let global = BinBuilder.bin(from: [.init(measurement: globalMeasurement, outputRan: anyOutput)],
                                    levelsTrusted: globalTrusted)
        // Only real measurements feed the global detector; "output ran" alone is the apps' job.
        let globalForDetection = global.flags.contains(.captured) ? global : .empty
        for i in first...index {
            allLane.history.write(global, at: i)
            globalDetector.feed(laneKey: allLane.id, index: i, bin: globalForDetection)
        }

        stopIdleTaps(at: index)
        let crossedPruneBoundary = index / 200 != lastIndex / 200
        lastIndex = index
        if crossedPruneBoundary { prune(before: index - BinClock.historyBins) }
        collectUnattributedSounds()
        publishEvents()
        updatePlayingSummary(at: index)
        // Recording continues regardless; redraws only matter while someone can see them.
        if publishWhileHidden || NSApp.windows.contains(where: { $0.isVisible && $0.occlusionState.contains(.visible) }) {
            currentIndex = index
        }
    }

    /// Running taps cost CPU in coreaudiod, so an app's tap stops after it's been quiet a while.
    /// Its next output restarts it (the all-audio tap covers the restart gap).
    private func stopIdleTaps(at index: Int) {
        for tracked in processes.values where tracked.tapActive && !tracked.isRunningOutput {
            guard let last = tracked.lastOutputIndex, index - last > Self.idleStopBins else { continue }
            tracked.tapActive = false
            taps.setActive(tracked.objectID, false)
        }
    }

    private func prune(before cutoff: Int) {
        detector.prune(before: cutoff)
        globalDetector.prune(before: cutoff)
        unattributedEvents.removeAll { $0.endIndex < cutoff }
        // Drop lanes for apps that are gone and have nothing left in the retained history.
        let referenced = Set(detector.events.map(\.laneKey))
        let stale = lanes.filter { lane in
            lane.liveProcessCount == 0 && !referenced.contains(lane.id)
                && (detector.lastSoundIndex(laneKey: lane.id) ?? .min) < cutoff
        }
        guard !stale.isEmpty else { return }
        let staleIDs = Set(stale.map(\.id))
        lanes.removeAll { staleIDs.contains($0.id) }
        for id in staleIDs { lanesByKey[id] = nil }
    }

    /// Lists finished all-audio sounds that no app lane accounts for as "Unknown app".
    private func collectUnattributedSounds() {
        let finished = globalDetector.events.filter { !$0.isOngoing && $0.id > attributedThroughID }
        guard let newest = finished.map(\.id).max() else { return }
        attributedThroughID = newest
        unattributedEvents += Attribution.unattributed(finished, appEvents: detector.events,
                                                       slackBins: Self.attributionSlackBins)
    }

    private func publishEvents() {
        var latest = detector.events
        if !unattributedEvents.isEmpty {
            latest += unattributedEvents
            latest.sort { $0.startIndex < $1.startIndex }
        }
        guard latest != events else { return }
        let previous = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        for event in latest.suffix(64) {
            let before = previous[event.id]
            if before == nil { event.isOngoing ? logStart(event) : logEnd(event) }
            if before?.isOngoing == true, !event.isOngoing { logEnd(event) }
        }
        events = latest
        sortLanesByMostRecentSound()
    }

    private func updatePlayingSummary(at index: Int) {
        let playing = lanes.filter { detector.isSounding($0.history[index]) }
        let summary = switch playing.count {
        case 0: "Quiet"
        case 1: "\(playing[0].name) is playing"
        default: "\(playing.count) apps playing"
        }
        if summary != playingSummary { playingSummary = summary }
    }

    /// Orders lanes by when their latest sound *started*, so two apps playing at once
    /// don't keep swapping places.
    private func sortLanesByMostRecentSound() {
        var latestStart: [String: Int] = [:]
        for event in events { latestStart[event.laneKey] = max(latestStart[event.laneKey] ?? .min, event.startIndex) }
        let sorted = lanes.enumerated().sorted { a, b in
            let sa = latestStart[a.element.id] ?? .min, sb = latestStart[b.element.id] ?? .min
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
        if sorted.map(\.id) != lanes.map(\.id) { lanes = sorted }
    }

    private func displayName(_ event: SoundEvent) -> String {
        event.laneKey == allLane.id ? "Unknown app" : lane(forKey: event.laneKey)?.name ?? event.laneKey
    }

    private func logStart(_ event: SoundEvent) {
        Log.events.info("sound started: \(self.displayName(event), privacy: .public)")
    }

    private func logEnd(_ event: SoundEvent) {
        let time = date(ofIndex: event.startIndex).formatted(date: .omitted, time: .standard)
        let duration = Formatting.duration(seconds: Double(event.binCount) * BinClock.binSeconds)
        Log.events.info("sound: \(self.displayName(event), privacy: .public) at \(time, privacy: .public) for \(duration, privacy: .public), peak \(Formatting.level(event.peak), privacy: .public)")
    }
}
