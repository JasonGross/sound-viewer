import CoreAudio
import Foundation
import os
import SoundCore

/// Collects levels from the real-time audio thread until the UI tick drains them, and tracks
/// whether its tap is healthy. The lock is held only for a few arithmetic operations.
final class LevelAccumulator: @unchecked Sendable {
    enum Health: Equatable {
        /// Tap not built yet, or built but its IO hasn't run.
        case pending
        /// The tap has delivered audio at least once.
        case delivering
        /// The tap couldn't be built; levels for this process are unknown.
        case failed
    }

    private struct State {
        var measurement = LevelMath.Measurement.zero
        var delivered = false
        var failed = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Called from the IOProc (real-time thread).
    func add(_ measurement: LevelMath.Measurement) {
        state.withLock {
            $0.measurement.merge(measurement)
            $0.delivered = true
        }
    }

    func drain() -> LevelMath.Measurement {
        state.withLock { s in
            defer { s.measurement = .zero }
            return s.measurement
        }
    }

    var health: Health {
        state.withLock { $0.failed ? .failed : $0.delivered ? .delivering : .pending }
    }

    func setFailed(_ failed: Bool) {
        state.withLock { $0.failed = failed }
    }
}

/// A private, unmuted Core Audio tap read through its own private aggregate device.
/// The tapped app's audio is untouched; we only measure it.
///
/// The aggregate contains *only* the tap: no physical sub-device. Including the output device
/// would also run its input side (a headset's microphone), which can flip Bluetooth headsets
/// into low-quality call mode and light the mic indicator.
final class ProcessTap {
    let label: String
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var isRunning = false

    /// `waitForAudio` starts IO only once the tapped process actually plays something
    /// (`kAudioAggregateDeviceTapAutoStartKey`), so idle taps cost nothing.
    init(description: CATapDescription, label: String, waitForAudio: Bool, accumulator: LevelAccumulator) throws {
        self.label = label
        description.name = "Sound Viewer: \(label)"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        do {
            try check(AudioHardwareCreateProcessTap(description, &tapID), "creating tap for \(label)")

            let format = try AudioProperty.read(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else {
                throw CoreAudioError(status: kAudioHardwareUnsupportedOperationError, operation: "unexpected tap format for \(label)")
            }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sound Viewer: \(label)",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: waitForAudio,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    // The tap is the only member, so there's no other clock to drift from.
                    kAudioSubTapDriftCompensationKey: false,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                      "creating aggregate device for \(label)")

            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, _, _ in
                // Real-time thread: no allocation, no logging, no locks beyond the accumulator's.
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                var measurement = LevelMath.Measurement.zero
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    measurement.merge(LevelMath.measure(
                        UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)))
                }
                accumulator.add(measurement)
            }, "creating IOProc for \(label)")

            try start()
            Log.audio.info("tapping \(label, privacy: .public)")
        } catch {
            invalidate()
            throw error
        }
    }

    func start() throws {
        guard !isRunning, let ioProcID else { return }
        try check(AudioDeviceStart(aggregateID, ioProcID), "starting \(label)")
        isRunning = true
    }

    func stop() {
        guard isRunning, let ioProcID else { return }
        AudioDeviceStop(aggregateID, ioProcID)
        isRunning = false
    }

    func invalidate() {
        stop()
        if aggregateID != .unknown {
            if let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID) }
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    deinit { invalidate() }
}
