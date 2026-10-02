import CoreAudio
import Foundation

/// Owns every tap. All Core Audio setup and teardown happens on a private serial queue,
/// because creating an aggregate device can take tens of milliseconds.
final class TapManager: @unchecked Sendable {
    /// Key used for the tap of all system audio.
    static let globalKey = AudioObjectID.unknown

    private struct Request {
        let label: String
        let accumulator: LevelAccumulator
        /// Whether IO should be running. Idle per-app taps are stopped to save power.
        var active = true
    }

    private static let maxAttempts = 3
    private static let retryDelay: TimeInterval = 3

    /// Called on the main queue whenever all taps are torn down and rebuilt, so the model can
    /// ignore the moment when no tap is delivering audio.
    var onRebuild: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "SoundViewer.taps", qos: .userInitiated)
    // Everything below is only touched on `queue`.
    private var requests: [AudioObjectID: Request] = [:]
    private var taps: [AudioObjectID: ProcessTap] = [:]
    private var attempts: [AudioObjectID: Int] = [:]
    /// Failed taps waiting for their retry.
    private var waitingToRetry: Set<AudioObjectID> = []
    private var enabled = false
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        // Rebuild when the output device changes or coreaudiod restarts (all IDs go stale).
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyServiceRestarted] {
            var address = propertyAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuildAll() }
            if AudioObjectAddPropertyListenerBlock(.system, &address, queue, block) == noErr {
                systemListeners.append((address, block))
            }
        }
    }

    /// Taps are only created while enabled (i.e. when we have permission to capture audio).
    func setEnabled(_ on: Bool) {
        queue.async {
            guard on != self.enabled else { return }
            self.enabled = on
            on ? self.buildMissing() : self.tearDownAll()
        }
    }

    func tap(_ processID: AudioObjectID, label: String, accumulator: LevelAccumulator) {
        queue.async {
            guard self.requests[processID] == nil else { return }
            self.requests[processID] = Request(label: label, accumulator: accumulator)
            self.buildMissing()
        }
    }

    func untap(_ processID: AudioObjectID) {
        queue.async {
            self.requests[processID] = nil
            self.attempts[processID] = nil
            self.waitingToRetry.remove(processID)
            self.taps.removeValue(forKey: processID)?.invalidate()
        }
    }

    /// Starts or stops a tap's IO without destroying it, so it can restart quickly.
    func setActive(_ processID: AudioObjectID, _ active: Bool) {
        queue.async {
            guard var request = self.requests[processID], request.active != active else { return }
            request.active = active
            self.requests[processID] = request
            guard let tap = self.taps[processID] else { return }
            Log.audio.info("\(active ? "resuming" : "pausing idle", privacy: .public) tap: \(request.label, privacy: .public)")
            if active {
                do { try tap.start() } catch { Log.audio.error("\(String(describing: error), privacy: .public)") }
            } else {
                tap.stop()
            }
        }
    }

    /// Recreates every tap, e.g. after the default output device changes.
    func rebuildAll() {
        queue.async {
            guard self.enabled else { return }
            if let onRebuild = self.onRebuild { DispatchQueue.main.async(execute: onRebuild) }
            self.tearDownAll()
            self.attempts.removeAll()
            self.waitingToRetry.removeAll()
            self.buildMissing()
        }
    }

    /// Synchronously removes every tap and aggregate device. Call before quitting.
    func shutdown() {
        queue.sync {
            for (address, block) in systemListeners {
                var address = address
                AudioObjectRemovePropertyListenerBlock(.system, &address, queue, block)
            }
            systemListeners.removeAll()
            enabled = false
            requests.removeAll()
            tearDownAll()
        }
    }

    private func buildMissing() {
        guard enabled else { return }
        for (processID, request) in requests where taps[processID] == nil && !waitingToRetry.contains(processID) {
            let isGlobal = processID == Self.globalKey
            let description = isGlobal
                ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
                : CATapDescription(stereoMixdownOfProcesses: [processID])
            do {
                // The all-audio tap runs from launch so nothing is missed; per-app taps start
                // with their app's first sound.
                let tap = try ProcessTap(description: description, label: request.label,
                                         waitForAudio: !isGlobal, accumulator: request.accumulator)
                if !request.active { tap.stop() }
                taps[processID] = tap
                attempts[processID] = nil
                request.accumulator.setFailed(false)
            } catch {
                Log.audio.error("\(String(describing: error), privacy: .public)")
                request.accumulator.setFailed(true)
                let attempt = (attempts[processID] ?? 0) + 1
                attempts[processID] = attempt
                if attempt < Self.maxAttempts {
                    waitingToRetry.insert(processID)
                    queue.asyncAfter(deadline: .now() + Self.retryDelay) {
                        self.waitingToRetry.remove(processID)
                        self.buildMissing()
                    }
                }
            }
        }
    }

    private func tearDownAll() {
        for tap in taps.values { tap.invalidate() }
        taps.removeAll()
    }
}
