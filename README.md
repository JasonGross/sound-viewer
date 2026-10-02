# Sound Viewer

A Mac app that shows which apps are making sound. Each app gets its own live waveform lane on
a shared timeline, and every sound is logged in a **Recent sounds** list, so when something
dings you can find out afterwards what it was.

- **Per-app waveforms** (peak and RMS on a dB scale), plus an "All sound" lane.
- **Recent sounds:** app, time, duration and peak level. Click one to jump to it on the timeline. If the "All sound" lane hears something no app accounts for, it's listed as **Unknown app**, so nothing audible goes unlisted.
- **Last 60 minutes** kept in memory. Drag or two-finger scroll the timeline to go back; pick 30 s / 2 m / 10 m / 60 m windows.
- **Helpers grouped under their app.** "Google Chrome Helper" and Safari's WebKit audio process show up as Chrome and Safari.
- **Doesn't touch your audio.** Taps are private and unmuted, and audio is only measured, never recorded or saved. No microphone is ever opened.
- **Cheap to leave running.** Near-zero CPU while the window is hidden. It doesn't stop your Mac from sleeping, and pauses each app's tap after 10 seconds without output.
- **Sees sounds even when your Mac is muted**, because it measures each app's output before system volume.

Requires macOS 14.4 or later.

## Build and run

Only the Xcode Command Line Tools are needed.

```bash
scripts/run.sh
```

That builds `build/Sound Viewer.app` and opens it. Use `scripts/build-app.sh` to build without
launching, and copy the app to `/Applications` if you want to keep it.

On first launch macOS asks for **System Audio Recording** permission. Without it, Sound Viewer
still shows *which* apps have audio running, but not how loud (lanes show a striped "level
unknown" band). You can change it later in System Settings → Privacy & Security → Screen & System
Audio Recording → System Audio Recording Only.

The app is ad-hoc signed, so macOS may ask for permission again after you rebuild it.

## Reading the timeline

| You see | Meaning |
|---|---|
| Solid waveform | The app's audio level (RMS inside, peak outside), −60 to 0 dBFS |
| Thin line on the center | The app has an audio stream open but it's silent (apps only get a lane once they're audible) |
| Striped band | The app was playing, but its level wasn't captured (no permission, or the first ~100 ms before a new app's tap starts) |

A sound counts as an event when it's above −50 dBFS. Sounds less than 1 second apart are
merged into one event.

## Known limits

- **Notification and alert sounds** usually come from a macOS system process, so they appear
  under **System sounds**, not under the app that posted the notification.
- **The first sound from an app that hasn't played in the last 10 seconds** can lose its first
  ~100 ms in that app's lane while its tap starts. It still shows up in the list and in the
  "All sound" lane.
- **When your Mac is muted, macOS doesn't play alert sounds at all**, so there's nothing to see.
- **History lives in memory and is lost when you quit.**

## Development

```bash
swift run SoundCoreTests      # unit tests for the pure logic in Sources/SoundCore
swift build                   # debug build of everything
log stream --predicate 'subsystem == "local.SoundViewer"' --level info   # app logs (taps, events)
```

- `Sources/SoundCore`: level math, history ring buffer, event detection, naming and formatting. No Core Audio, fully tested.
- `Sources/SoundViewer/Audio`: Core Audio process watching, app resolution and taps.
- `Sources/SoundViewer/Monitor.swift`: the model. A 20 Hz tick turns taps into history and events.
- `Sources/SoundViewer/Views`: SwiftUI.
- `docs/design.md`: design notes and decisions.

`open --env SOUNDVIEWER_SNAPSHOT=/tmp/sv.png "build/Sound Viewer.app"` makes the app write a
PNG of its window every 2 seconds, which is handy for checking the UI from scripts.
`scripts/make-icon.swift` regenerates the app icon.

## License

MIT. See [LICENSE](LICENSE).
