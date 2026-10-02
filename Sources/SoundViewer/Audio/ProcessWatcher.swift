import CoreAudio
import Foundation

/// Tracks Core Audio's audio processes and whether each one has output running.
///
/// Needs no permission. Listener blocks run on the main queue.
@MainActor
final class ProcessWatcher {
    struct AudioProcess {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String
        var isRunningOutput: Bool
    }

    private(set) var processes: [AudioObjectID: AudioProcess] = [:]

    var onAdded: ((AudioProcess) -> Void)?
    var onRemoved: ((AudioProcess) -> Void)?
    /// Fired when a process starts or stops output (or IO changes while output runs).
    /// Consumers should treat every call as "output ran just now".
    var onOutputActivity: ((AudioProcess) -> Void)?

    private var listListener: AudioObjectPropertyListenerBlock?
    private var outputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    func start() {
        guard listListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        let status = AudioObjectAddPropertyListenerBlock(.system, &address, .main, block)
        if status != noErr { Log.audio.error("process list listener failed: \(fourCharCode(status), privacy: .public)") }
        listListener = block
        refresh()
    }

    func stop() {
        if let block = listListener {
            var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(.system, &address, .main, block)
            listListener = nil
        }
        for id in Array(outputListeners.keys) { removeOutputListener(id) }
        processes.removeAll()
    }

    private func refresh() {
        let ids = (try? AudioProperty.readArray(.system, kAudioHardwarePropertyProcessObjectList,
                                                element: AudioObjectID.unknown)) ?? []
        let current = Set(ids)
        for (id, process) in processes where !current.contains(id) {
            removeOutputListener(id)
            processes[id] = nil
            onRemoved?(process)
        }
        for id in ids where processes[id] == nil { add(id) }
    }

    private func add(_ id: AudioObjectID) {
        guard let pid = try? AudioProperty.read(id, kAudioProcessPropertyPID, initial: pid_t(-1)),
              pid > 0, pid != getpid() else { return }
        let bundleID = (try? AudioProperty.readString(id, kAudioProcessPropertyBundleID)) ?? ""

        // Listen before reading the initial state, so output that starts in between still
        // notifies us. (Notifications arrive on the main queue, after this function returns.)
        let block: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
            let deviceChange = (0..<Int(count)).contains { addresses[$0].mSelector == kAudioProcessPropertyDevices }
            MainActor.assumeIsolated { self?.outputChanged(id, outputDevicesChanged: deviceChange) }
        }
        for var address in Self.ioChangeAddresses {
            AudioObjectAddPropertyListenerBlock(id, &address, .main, block)
        }
        outputListeners[id] = block

        let process = AudioProcess(objectID: id, pid: pid, bundleID: bundleID, isRunningOutput: isRunningOutput(id))
        processes[id] = process
        onAdded?(process)
    }

    /// `kAudioProcessPropertyIsRunningOutput` doesn't send change notifications on macOS 26
    /// (verified), but `IsRunning` and the output device list do, ~40 ms after a process starts
    /// or stops IO. We listen to all three (IsRunningOutput as insurance on older systems) and
    /// re-read the output flag.
    private static let ioChangeAddresses = [
        propertyAddress(kAudioProcessPropertyIsRunningOutput),
        propertyAddress(kAudioProcessPropertyIsRunning),
        propertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput),
    ]

    private func outputChanged(_ id: AudioObjectID, outputDevicesChanged: Bool) {
        guard var process = processes[id] else { return }
        let wasRunning = process.isRunningOutput
        process.isRunningOutput = isRunningOutput(id)
        processes[id] = process
        // IsRunning also changes for input-only (microphone) IO; ignore that. A change to the
        // *output* device list does mean output ran, even if a short blip already stopped.
        if wasRunning || process.isRunningOutput || outputDevicesChanged { onOutputActivity?(process) }
    }

    private func isRunningOutput(_ id: AudioObjectID) -> Bool {
        ((try? AudioProperty.read(id, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0) != 0
    }

    private func removeOutputListener(_ id: AudioObjectID) {
        guard let block = outputListeners.removeValue(forKey: id) else { return }
        for var address in Self.ioChangeAddresses {
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
    }
}
