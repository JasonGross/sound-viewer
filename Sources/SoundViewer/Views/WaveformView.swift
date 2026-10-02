import SoundCore
import SwiftUI

enum LanePalette {
    private static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .red, .mint, .indigo, .cyan, .brown]

    static func color(_ index: Int) -> Color {
        index < 0 ? Color(nsColor: .secondaryLabelColor) : colors[index % colors.count]
    }
}

/// A lane's levels over the visible range, drawn as a mirrored envelope on a dB scale:
/// peak (light) around RMS (solid). A thin line marks an open-but-silent output stream;
/// a striped band marks output that ran while we couldn't measure it.
struct WaveformView: View {
    let history: LevelHistory
    let laneKey: String
    let range: Range<Int>
    let color: Color
    let hoverIndex: Int?
    let highlight: SoundEvent?

    var body: some View {
        Canvas { context, size in
            let columns = max(1, Int(size.width))
            let bins = history.columns(from: range.lowerBound, to: range.upperBound, count: columns)
            let columnWidth = size.width / CGFloat(columns)
            let mid = size.height / 2
            let half = size.height / 2 - 2

            func x(_ index: Int) -> CGFloat {
                CGFloat(index - range.lowerBound) / CGFloat(range.count) * size.width
            }

            context.fill(Path(CGRect(x: 0, y: mid - 0.25, width: size.width, height: 0.5)),
                         with: .color(.secondary.opacity(0.2)))

            if let highlight, highlight.laneKey == laneKey {
                let x0 = x(highlight.startIndex), x1 = max(x(highlight.endIndex + 1), x0 + 3)
                let rect = CGRect(x: x0 - 2, y: 1, width: x1 - x0 + 4, height: size.height - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.accentColor.opacity(0.18)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(.accentColor.opacity(0.7)), lineWidth: 1)
            }

            var peak = Path(), rms = Path(), stream = Path(), unknown = Path()
            for (i, bin) in bins.enumerated() {
                let left = CGFloat(i) * columnWidth
                if bin.flags.contains(.captured) {
                    let hp = CGFloat(LevelMath.displayHeight(linear: bin.peak)) * half
                    let hr = CGFloat(LevelMath.displayHeight(linear: bin.rms)) * half
                    if hp >= 0.5 { peak.addRect(CGRect(x: left, y: mid - hp, width: columnWidth, height: hp * 2)) }
                    if hr >= 0.5 { rms.addRect(CGRect(x: left, y: mid - hr, width: columnWidth, height: hr * 2)) }
                    if hp < 0.5, bin.flags.contains(.active) {
                        stream.addRect(CGRect(x: left, y: mid - 1, width: columnWidth, height: 2))
                    }
                } else if bin.flags.contains(.active), (i / 2) % 2 == 0 {
                    unknown.addRect(CGRect(x: left, y: mid - half * 0.6, width: columnWidth, height: half * 1.2))
                }
            }
            context.fill(unknown, with: .color(color.opacity(0.35)))
            context.fill(stream, with: .color(color.opacity(0.55)))
            context.fill(peak, with: .color(color.opacity(0.35)))
            context.fill(rms, with: .color(color.opacity(0.95)))

            if let hoverIndex, range.contains(hoverIndex) {
                context.fill(Path(CGRect(x: x(hoverIndex), y: 0, width: 1, height: size.height)),
                             with: .color(.primary.opacity(0.45)))
            }
        }
    }
}
