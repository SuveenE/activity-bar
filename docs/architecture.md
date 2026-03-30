# Architecture

| File | Purpose |
|---|---|
| `InputStatsApp.swift` | App entry point, AppDelegate, menu bar setup, floating panel lifecycle |
| `Models.swift` | `DailyStats` and `AppStats` data models |
| `StatsStore.swift` | Observable store with daily counters and UserDefaults persistence |
| `EventMonitors.swift` | CGEvent tap monitoring for keys, clicks, scrolls; screen time tracking |
| `SpeechDetector.swift` | CoreAudio-based microphone state detection with per-device listeners |
| `MenuBarView.swift` | Menu bar popover UI with expandable app rows, trend charts |
| `DashboardView.swift` | Full dashboard with stat cards, per-app table, 7-day charts |
| `FloatingPanel.swift` | Custom `NSPanel` subclass with transparent hosting and anchor positioning |
