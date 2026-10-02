import SoundCore
import SwiftUI

/// "Recent sounds": one row per detected sound, newest first.
struct EventList: View {
    @Environment(Monitor.self) private var monitor
    @Binding var selection: SoundEvent.ID?
    /// Called on every click, even on the already-selected row, so it always jumps back.
    let onSelect: (SoundEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent sounds").font(.headline)
                Spacer()
                Button("Clear") {
                    selection = nil
                    monitor.clearEvents()
                }
                .disabled(monitor.events.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()

            if monitor.events.isEmpty {
                ContentUnavailableView("No sounds yet", systemImage: "waveform",
                                       description: Text("When an app makes a sound, it shows up here. Click one to find it on the timeline."))
            } else {
                // A plain scroll view (not List) so new sounds appear at the top in view,
                // instead of the list keeping its anchor and pushing them out of sight.
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(monitor.events.reversed()) { event in
                            EventRow(event: event, lane: monitor.lane(forKey: event.laneKey),
                                     isUnattributed: event.laneKey == monitor.allLane.id,
                                     start: monitor.date(ofIndex: event.startIndex))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(selection == event.id ? Color.accentColor.opacity(0.22) : .clear))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = event.id
                                    onSelect(event)
                                }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: SoundEvent
    let lane: Lane?
    /// Heard by the all-audio tap, but no app accounts for it.
    let isUnattributed: Bool
    let start: Date

    var body: some View {
        HStack(spacing: 8) {
            if isUnattributed {
                LaneIcon(icon: .symbol("questionmark"), size: 22)
            } else if let lane {
                LaneIcon(icon: lane.icon, size: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(isUnattributed ? "Unknown app" : lane?.name ?? event.laneKey)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .help(isUnattributed ? "Heard in All sound, but no app's own audio matched it" : "")
                    Spacer(minLength: 4)
                    Text(start, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if event.isOngoing {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Playing")
                        Text("·")
                    }
                    Text(Formatting.duration(seconds: Double(event.binCount) * BinClock.binSeconds))
                    Text("·")
                    Text(event.peak == nil ? "level unknown" : "peak " + Formatting.level(event.peak))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PermissionBanner: View {
    let status: AudioPermission.Status

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(status == .denied ? "Sound Viewer can't hear apps yet" : "Waiting for permission to hear apps")
                    .font(.headline)
                Text("It can still see which apps are playing audio, but not how loud. Turn on Sound Viewer in Privacy & Security → Screen & System Audio Recording, under System Audio Recording Only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open System Settings") { NSWorkspace.shared.open(AudioPermission.settingsURL) }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12))
    }
}
