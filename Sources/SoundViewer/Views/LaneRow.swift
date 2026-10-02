import SoundCore
import SwiftUI

enum LaneLayout {
    static let headerWidth: CGFloat = 220
    static let rowHeight: CGFloat = 54
}

struct LaneIcon: View {
    let icon: AppIdentity.Icon
    var size: CGFloat = 24

    var body: some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(.quaternary))
        }
    }
}

/// Vertical peak meter on the same dB scale as the waveform.
struct LevelMeter: View {
    let level: Float?

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(LevelMath.displayHeight(linear: level ?? 0))
            ZStack(alignment: .bottom) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(height: geo.size.height * fraction)
            }
        }
        .frame(width: 5)
    }

    private var color: Color {
        let db = LevelMath.decibels(level ?? 0)
        return db > -3 ? .red : db > -12 ? .yellow : .green
    }
}

/// One lane: who it is and what it's doing now (or at the hovered time), then its waveform.
struct LaneRow: View {
    @Environment(Monitor.self) private var monitor
    let lane: Lane
    let viewport: Viewport
    var isSummary = false

    @State private var dragAnchor: Int?
    @State private var waveformWidth: Double = 1

    var body: some View {
        let current = monitor.currentIndex
        let range = viewport.range(current: current)
        let shownIndex = viewport.hoverIndex ?? current
        let bin = lane.history[shownIndex]
        let highlight = viewport.highlightLaneKey == lane.id
            ? monitor.events.last { $0.id == viewport.highlightID } : nil

        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LaneIcon(icon: lane.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(status(bin: bin, current: current))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(bin.flags.contains(.captured) && LevelMath.displayHeight(linear: bin.peak) > 0
                     ? Formatting.level(bin.peak) : "")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                LevelMeter(level: bin.flags.contains(.captured) ? bin.peak : nil)
                    .frame(height: LaneLayout.rowHeight - 18)
            }
            .padding(.horizontal, 10)
            .frame(width: LaneLayout.headerWidth)
            .help(lane.processNames.isEmpty ? lane.name : "Processes: " + lane.processNames.joined(separator: ", "))

            Divider()

            WaveformView(history: lane.history, laneKey: lane.id, range: range,
                         color: LanePalette.color(lane.colorIndex),
                         hoverIndex: viewport.hoverIndex, highlight: highlight)
                .contentShape(Rectangle())
                .onGeometryChange(for: Double.self) { $0.size.width } action: { waveformWidth = max(1, $0) }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let fraction = point.x / waveformWidth
                        viewport.hoverIndex = range.lowerBound + Int(fraction * Double(range.count))
                    case .ended:
                        viewport.hoverIndex = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let anchor = dragAnchor ?? range.upperBound - 1
                        dragAnchor = anchor
                        let bins = Int((-value.translation.width * Double(viewport.spanBins)
                                        / waveformWidth).rounded())
                        viewport.setEnd(anchor + bins, current: monitor.currentIndex)
                    }
                    .onEnded { _ in dragAnchor = nil })
        }
        .frame(height: LaneLayout.rowHeight)
        .background(isSummary ? Color.secondary.opacity(0.06) : .clear)
    }

    private func status(bin: LevelBin, current: Int) -> String {
        if isSummary { return viewport.hoverIndex == nil ? "All apps combined" : "At pointer" }
        let sounding = monitor.detector.isSounding(bin)
        let prefix = viewport.hoverIndex == nil ? "" : "At pointer: "
        if sounding { return prefix + (bin.flags.contains(.captured) ? "Playing" : "Playing (level unknown)") }
        if bin.flags.contains(.active) { return prefix + "Stream open, silent" }
        if viewport.hoverIndex != nil { return "At pointer: quiet" }
        if lane.liveProcessCount == 0 { return "Quit" }
        if let last = monitor.detector.lastSoundIndex(laneKey: lane.id) {
            return "Last sound " + Self.ago(seconds: Double(current - last) * BinClock.binSeconds)
        }
        return "Idle"
    }

    private static func ago(seconds: Double) -> String {
        switch seconds {
        case ..<60: return "\(max(1, Int(seconds))) s ago"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        default: return "over an hour ago"
        }
    }
}
