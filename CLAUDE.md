# Grañipa — agent notes

Native macOS (26+) SwiftUI meeting recorder/transcriber. SPM executable target
`Granipa`, bundled into `build/Grañipa.app` by `Scripts/bundle.sh`. No Xcode project.

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
- `Diarization/` — pure mapping logic (`SpeakerMapping`) + `DiarizationService`
  behind `#if canImport(FluidAudio)` (dependency intentionally commented out in
  Package.swift until the user enables it).
- `LLM/` — subprocess adapters for claude/codex/gemini/grok CLIs (subscription
  auth, no API keys). `EnhancementService` builds one strict-JSON prompt
  (title/summary/enhanced_notes/action_items/email_draft).
- `API/` — hand-rolled HTTP server on NWListener (localhost + bearer token),
  `APIRouter` is pure and unit-tested; HMAC-signed webhooks with a persisted
  retry queue.
- `Calendar/`, `Detection/` — EventKit upcoming meetings; CoreAudio process list
  polling to detect meeting apps using the mic.
- `Storage/AppDatabase.swift` — GRDB, append-only migrations (v1..v3).
- `AppState.swift` — MainActor orchestrator: record -> transcribe -> postProcess
  (diarize -> enhance -> webhooks).

## Conventions

- Swift 6 strict concurrency; no `@preconcurrency` escapes — fix captures with
  Sendable boxes where AVFoundation callbacks require it.
- Timestamps are meeting-relative seconds everywhere (transcript, diarization, API).
- Migrations are append-only; never reorder.
- TCC pitfalls: ad-hoc signing resets audio grants per rebuild; UNUserNotificationCenter
  crashes outside a real .app bundle (guarded in `NotificationManager.isAvailable`).
