import SoundCore
import SwiftUI

/// Clock-time labels for the visible range, plus the time under the pointer.
///
/// Labels are ordinary `Text` views keyed by their tick time, so SwiftUI keeps their layout
/// and only moves them each frame. (Drawing the text inside the Canvas re-laid it out on every
/// tick and was the single biggest CPU cost of the live view.)
struct TimeAxis: View {
    let range: Range<Int>
    let hoverIndex: Int?
    let date: (Int) -> Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        let span = Double(range.count) * BinClock.binSeconds
        let step = Formatting.tickInterval(forSpanSeconds: span)
        let t0 = date(range.lowerBound).timeIntervalSinceReferenceDate
        let ticks = Array(stride(from: (t0 / step).rounded(.up) * step, through: t0 + span, by: step))

        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) -> CGFloat in CGFloat((t - t0) / span) * width }

            ZStack(alignment: .leading) {
                Canvas { context, size in
                    for t in ticks {
                        context.fill(Path(CGRect(x: x(t), y: size.height - 6, width: 1, height: 6)),
                                     with: .color(.secondary.opacity(0.6)))
                    }
                }
                ForEach(ticks, id: \.self) { t in
                    Text(verbatim: Self.formatter.string(from: Date(timeIntervalSinceReferenceDate: t)))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: x(t) + 3, y: -1)
                }
                if let hoverIndex, range.contains(hoverIndex) {
                    let px = CGFloat(hoverIndex - range.lowerBound) / CGFloat(range.count) * width
                    Text(verbatim: Self.formatter.string(from: date(hoverIndex)))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                        .fixedSize()
                        // Center on the pointer, kept inside the axis.
                        .alignmentGuide(.leading) { d in -min(max(0, px - d.width / 2), width - d.width) }
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .clipped()
    }
}
