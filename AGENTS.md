# Grañipa — agent notes

Native macOS (26+) SwiftUI meeting recorder/transcriber. SPM executable targets
`Granipa` and `GranipaBatteryHelper`, bundled into `build/Grañipa.app` by
`Scripts/bundle.sh`. No Xcode project. Product state: `CONTEXT.md`.

## Commands

- Build: `swift build`
- Tests: `swift test` (swift-testing, includes a live TCP test of the API server)
- App bundle: `./Scripts/bundle.sh [release]`

## Architecture (Sources/Granipa/)

- `Audio/` — `SystemAudioTap` (Core Audio process tap of all system output),
  `MicRecorder` (AVAudioEngine + optional voice-processing AEC), `RecordingSession`
  (writes m4a per channel, pads system-channel gaps with silence so file time ==
  meeting time, fans out `AudioChunk` AsyncStreams).
- `Transcription/` — two SpeechAnalyzer/SpeechTranscriber sessions (mic="Me",
  system="Them"); volatile results go to UI, final results to DB.
- `Dictation/` — hold-to-talk overlay (default Right Option). Mic ASR is Apple
  on-device by default. Optional text rewrite via SpaceXAI (`api.x.ai`) or a
  custom OpenAI-compatible URL (Mac Mini / VPS). Muse on dictation is opt-in
  and sends the mic — meetings should use Muse on the system channel instead.
- Meetings: mic channel always Apple; system channel can be Apple or Muse
  (computer audio only). Muse diarization skips FluidAudio for that meeting.
- `Diarization/` — `SpeakerMapping` + `DiarizationService` via FluidAudio 0.15.2
  (linked in Package.swift). Offline, post-meeting, system channel only.
- `LLM/` — subprocess adapters for claude/codex/gemini/grok CLIs (subscription
  auth). Cloud ASR (Muse) is a separate opt-in; enhancement still uses CLIs.
  `EnhancementService` builds one strict-JSON prompt
  (title/summary/enhanced_notes/action_items/email_draft).
- `API/` — hand-rolled HTTP server on NWListener (localhost + bearer token),
  `APIRouter` is pure and unit-tested; HMAC-signed webhooks with a persisted
  retry queue.
- `Calendar/`, `Detection/` — EventKit upcoming meetings; CoreAudio process list
  polling to detect meeting apps using the mic.
- `Storage/AppDatabase.swift` — GRDB, append-only migrations (v1..v8).
- `AppState.swift` — MainActor orchestrator: record -> transcribe -> postProcess
  (diarize -> enhance -> webhooks).
- `UI/` — V2 shell: `MainWindow`, `HomeView` (All/Notes/Recordings filters),
  Dictation library, meeting detail/live, in-app `SettingsView`, `Theme`.
  Sidebar destinations are Home and Dictation only.
- `System/` — hotkeys/macro key, Sparkle, permission health, window manager.
  `BatteryService` is IOKit readout + optional SMC charge limit (opt-in).
  Writes go through `GranipaBatteryHelper` (SMAppService daemon). Restores
  charging on quit.
- `Fixture/` — DEBUG-only `--v2-fixture`. Refuses to open the production DB.

## Conventions

- Swift 6 strict concurrency; no `@preconcurrency` escapes — fix captures with
  Sendable boxes where AVFoundation callbacks require it.
- Timestamps are meeting-relative seconds everywhere (transcript, diarization, API).
- Migrations are append-only; never reorder.
- TCC pitfalls: ad-hoc signing resets audio grants per rebuild; UNUserNotificationCenter
  crashes outside a real .app bundle (guarded in `NotificationManager.isAvailable`).
