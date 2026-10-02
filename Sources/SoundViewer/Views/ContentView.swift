import SoundCore
import SwiftUI

struct ContentView: View {
    @Environment(Monitor.self) private var monitor
    @State private var viewport = Viewport()
    @State private var selection: SoundEvent.ID?

    var body: some View {
        HSplitView {
            Timeline(viewport: viewport)
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            EventList(selection: $selection) { event in
                viewport.show(event, current: monitor.currentIndex)
            }
            .frame(minWidth: 250, idealWidth: 310, maxWidth: 460, maxHeight: .infinity)
        }
        .navigationTitle("Sound Viewer")
        .navigationSubtitle(monitor.playingSummary)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Time window", selection: Bindable(viewport).spanSeconds) {
                    ForEach(Viewport.spans, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                .pickerStyle(.segmented)
                .help("How much time the timeline shows")

                Button {
                    viewport.goLive()
                    selection = nil
                } label: {
                    Label("Now", systemImage: "forward.end.fill")
                }
                .disabled(viewport.isLive && viewport.highlightID == nil)
                .help("Jump back to live")
            }
        }
    }
}

/// Time axis, the pinned "All sound" lane, then one lane per app.
private struct Timeline: View {
    @Environment(Monitor.self) private var monitor
    let viewport: Viewport
    @State private var scrollMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if monitor.permission != .authorized { PermissionBanner(status: monitor.permission) }

            HStack(spacing: 0) {
                Text(viewport.isLive ? "Live" : "Scrolled back. Drag or use Now to return.")
                    .font(.caption)
                    .foregroundStyle(viewport.isLive ? Color.green : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(width: LaneLayout.headerWidth, alignment: .leading)
                Divider()
                LiveTimeAxis(viewport: viewport)
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { viewport.waveformWidth = $0 }
            }
            .frame(height: 26)
            Divider()

            LaneRow(lane: monitor.allLane, viewport: viewport, isSummary: true)
            Divider()

            if monitor.lanes.isEmpty {
                ContentUnavailableView("Nothing has played yet", systemImage: "speaker.wave.2",
                                       description: Text("Each app gets its own lane the first time it plays sound."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(monitor.lanes) { lane in
                                LaneRow(lane: lane, viewport: viewport)
                                Divider()
                            }
                        }
                    }
                    // A visible scroll bar would make these lanes narrower than the time axis
                    // and the pinned "All sound" lane, misaligning times.
                    .scrollIndicators(.never)
                    .onChange(of: viewport.jumpCount) { _, _ in
                        guard let key = viewport.highlightLaneKey else { return }
                        withAnimation { proxy.scrollTo(key, anchor: .center) }
                    }
                }
            }
        }
        .onAppear(perform: installScrollPanning)
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
    }

    /// Two-finger horizontal scrolling over the waveforms pans through history.
    private func installScrollPanning() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard viewport.hoverIndex != nil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 10
            viewport.pan(byPoints: Double(dx), current: monitor.currentIndex)
            return nil
        }
    }
}

/// Reads the per-tick index itself, so only the axis redraws each tick, not the whole timeline.
private struct LiveTimeAxis: View {
    @Environment(Monitor.self) private var monitor
    let viewport: Viewport

    var body: some View {
        TimeAxis(range: viewport.range(current: monitor.currentIndex),
                 hoverIndex: viewport.hoverIndex, date: monitor.date(ofIndex:))
    }
}
