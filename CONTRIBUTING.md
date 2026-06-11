# Contributing

Thanks for your interest! Ground rules:

## Setup

```sh
git clone <your fork>
cd granipa
swift build && swift test
./Scripts/bundle.sh && open "build/Grañipa.app"
```

Requires macOS 26+ and the Xcode 26 toolchain. There is no Xcode project — this is a plain SwiftPM package; any editor works.

## Before opening a PR

1. `swift build` — zero errors, **zero warnings**.
2. `swift test` — all tests pass; new logic comes with tests.
3. Swift 6 strict concurrency — no `@preconcurrency` escapes; fix captures properly.
4. Database migrations are **append-only** — never edit or reorder existing ones.
5. Keep changes scoped — one feature/fix per PR, no drive-by refactors.

## Architecture

See [CLAUDE.md](CLAUDE.md) for the module map. The short version: `AppState` (MainActor) orchestrates; `Audio/` captures two channels; `Transcription/` runs SpeechAnalyzer sessions; `LLM/` shells out to subscription CLIs (never API keys); `API/` is a hand-rolled HTTP server with pure, unit-tested routing.

## Conventions

- Timestamps are meeting-relative seconds everywhere.
- UI strings in English; transcription supports en/es.
- No new dependencies without prior discussion in an issue.
