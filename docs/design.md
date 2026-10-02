# Sound Viewer — design

A macOS app that shows which apps are making sound, with a per-app waveform on a shared,
scrollable timeline and a list of recent sounds.

## Goals (in priority order)

1. **Find mystery sounds.** When a short sound plays (a ding, a blip), you can find out
   afterwards which app made it. History matters more than the live view.
2. **Glanceable live view** of which apps are making sound right now.
3. **Trustworthy levels.** Tell real silence apart from quiet audio.

Out of scope: microphone/input audio, persisting history to disk, menu-bar mode.
History is in memory for the last 60 minutes and is lost on quit.

## Platform

- macOS 14.4+ (developed on macOS 26), Apple Silicon and Intel.
- SwiftPM package; `scripts/build-app.sh` wraps the binary into an ad-hoc-signed
  `Sound Viewer.app` (needed so macOS can ask for audio-capture permission).
- Needs **System Audio Recording** permission (Privacy & Security → Screen & System Audio
  Recording). Without it the app falls back to activity-only mode (which apps have an
  output stream running), with no levels.

## How it works

| Unit | Job |
|---|---|
| `ProcessWatcher` | Tracks Core Audio's process list (`kAudioHardwarePropertyProcessObjectList`) and whether each process has output running. No permission needed. Note: `kAudioProcessPropertyIsRunningOutput` never sends change notifications (verified on macOS 26), so it also listens to `kAudioProcessPropertyIsRunning` and the output-scope `kAudioProcessPropertyDevices`, which fire ~40 ms after IO starts, and re-reads the output flag. An output-device-list change counts as output activity even if a short blip has already stopped. Listeners are registered before the initial read so nothing slips in between. |
| `AppResolver` | pid → user-facing app. Helpers are grouped under the app responsible for them (`responsibility_get_pid_responsible_for_pid`, falling back to the outermost `.app` in the executable path). Known system daemons get friendly names (e.g. `systemsoundserverd` → "System sounds"). |
| `TapManager` | One **global tap** (all system audio, running continuously from launch) plus a **per-process tap** created the first time a process starts output. Known system-sound daemons get their tap (and aggregate) created at launch, with IO waiting for their first audio (`kAudioAggregateDeviceTapAutoStartKey`). Taps are private and unmuted. Each tap gets its own private aggregate device containing **only the tap**: including the output device would also run its input side (a headset mic), which can switch Bluetooth headsets into call mode. A per-process tap's IO is paused after 10 s without output and resumed on the next output, because every running aggregate costs coreaudiod CPU (measured: ~12–14% with always-running per-app taps vs ~4% now, ~2.5% with no app). Failed taps are retried (3 attempts) and reported via the accumulator's health so that process falls back to activity-only. Rebuilt on default-output-device change and coreaudiod restart. Runs on its own serial queue. |
| `LevelAccumulator` | Written by the IOProc (real-time thread): running max peak and sum of squares, behind an uncontended unfair lock. Drained by the UI tick. Also tracks tap health: pending / delivering / failed. |
| `LevelHistory` | Per-lane ring buffer of 50 ms bins × 60 min (72,000 bins). Each bin: max peak, RMS, and flags (`captured` = a tap delivered audio; `active` = output was running at any point in the bin). |
| `EventDetector` | Turns bins into discrete sound events per lane. A bin is *sounding* if it was captured with peak above −50 dBFS, or if output was running but it wasn't captured (level unknown). Gaps shorter than 1 s are merged into one event. |
| `BinBuilder.outputCounts` | Decides when uncaptured output counts: only if it *just started* (within 1 s, while its tap spins up) or levels can't be captured (no permission, failed tap). A stream that was already open while taps (re)start doesn't produce a fake "level unknown" event. In addition, the monitor only honors "just started" when the always-running global tap heard something in that bin, and not for 2 s after taps are rebuilt, so apps opening silent streams (browsers, chat apps) don't create events. Lanes are created only when an app is audible. |
| `Attribution` | Sounds the global tap heard that overlap no app's event (process exited before it could be identified, tap failed, …) are listed as "Unknown app", so nothing audible goes unlisted. |
| `Monitor` | Main-actor model. A 20 Hz tick drains accumulators into history, runs event detection, and bumps a revision counter that drives redraws. Recording always continues, but the redraw counter only advances while the window is visible, and only leaf views read it (re-rendering the whole window per tick re-laid-out the toolbar and cost ~25% CPU). |

**Honest limits:** the first sound from an app that hasn't played recently can lose its first
~100 ms in its own lane while its tap starts or resumes (system-sound daemons included, since
their IO waits for audio). The app is still identified, via the activity flag and the
always-running "All sound" lane. The app also sets `kAudioHardwarePropertySleepingIsAllowed`;
otherwise coreaudiod holds a sleep assertion for as long as any tap runs, and the Mac never
idle-sleeps.

## UI

- Toolbar: time window (30 s / 2 m / 10 m / 60 m), "Now" button (shown when scrolled back).
- Timeline: pinned "All sound" lane, then one lane per app ordered by most recent sound.
  Each lane: icon, name, status (Playing / Silent stream / Idle / Quit), live meter, and a
  mirrored waveform (peak outer, RMS inner) on a dB scale (−60…0 dBFS) so quiet sounds
  stay visible. Output-running-but-silent shows as a thin baseline; output-running-but-not-
  captured shows as a hatched band.
- Clock-time axis; hover crosshair shows the time and each lane's level at that moment.
  Drag or two-finger scroll to pan back through history.
- Sidebar: "Recent sounds", newest first: app, time, duration, peak. Clicking one jumps
  the timeline to it and highlights it. (A plain scroll view rather than `List`, which kept
  its scroll anchor and pushed new sounds out of view.)
- Banner when audio-capture permission is missing, with a button to open System Settings.

## Testing

- `SoundCore` (pure Swift, no Core Audio) holds level math, history, event detection,
  app-naming rules, and waveform downsampling. Covered by `swift run SoundCoreTests`
  (a plain test runner, so it works with Command Line Tools only).
- End-to-end: launch the app, play known sounds with `afplay`, check the events it logs
  through `os_log` (subsystem `local.SoundViewer`).
