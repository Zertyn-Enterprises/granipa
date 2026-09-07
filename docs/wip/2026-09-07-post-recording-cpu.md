# Post-recording CPU — 2026-09-07

User report: after Stop, CPU spikes for minutes. Activity Monitor showed
`localspeechrecognition` at 167% (7 threads) and then `Grañipa` at 150%
(21 threads). The installed app was 2.0.1 build 8 from `feat/granipa-v2`
(release build), so the measurements and changes target that lane.

## What runs after Stop (default: live ASR off)

1. `FileMeetingTranscriber.transcribe` — locale probes (15 s of mic audio per
   candidate locale, `en-US,es-ES,es-US` → two probes), then one
   `SpeechAnalyzer` per channel over the whole m4a.
2. `postProcess` — FluidAudio offline diarization of the system channel,
   speaker-name inference (LLM CLI), enhancement (LLM CLI), webhooks.

## Measurements (real meeting `226FA000…`, 1434 s, Spanish, release builds)

ASR harness (standalone SpeechAnalyzer, CPU seconds from `rusage` and `ps`):

| Run | Wall | App CPU | Recognizer CPU | Finals | Chars |
|---|---:|---:|---:|---:|---:|
| system.m4a, `analyzeSequence(from:)` | 56.5 s | 4.8 s | 58.6 s | 106 | 12150 |
| system.m4a, manual chunks + silence gate (69% fed) | 99.3 s | 6.7 s | 79.1 s | 178 | 12171 |
| mic.m4a, `analyzeSequence(from:)` | 44.6 s | 3.6 s | 52.5 s | 121 | 12716 |
| mic.m4a, manual chunks + silence gate (100% fed) | 76.3 s | 8.1 s | 64.3 s | 122 | 12704 |
| es-ES probe, volatile results | 11.7 s | 0.2 s | 2.2 s | 2 | 190 |
| es-ES probe, finals only | 6.9 s | 0.2 s | 2.0 s | 2 | 190 |
| en-US probe, volatile results | 19.3 s | 0.1 s | 4.7 s | 0 | 0 |
| en-US probe, finals only | 13.4 s | 0.1 s | 4.2 s | 0 | 0 |

Wall times above were taken while a release build ran in parallel; the CPU
columns are the comparable numbers. Conclusions: the recognizer's ~1 CPU
second per 25 s of audio per channel is the inherent cost; the app's own
share of transcription is ~4 s per channel; feeding chunks ourselves with a
silence gate is worse on both channels (more XPC traffic, more restamps,
shorter finals), so `analyzeSequence(from:)` stays.

Diarization harness (FluidAudio 0.15.2 `OfflineDiarizerManager` on
system.m4a, `swift test -c release`):

| Config | Prepare | Process wall | Process CPU | Segments | Speakers |
|---|---:|---:|---:|---:|---:|
| default | 5.0 s | 35.1 s | 29.4 s | 152 | 2 |
| `embedding.skipStrategy = .maskSimilarity(0.95)` | 0.8 s | 24.2 s | 25.4 s | 152 | 2 |

The two segment lists are byte-identical (`diff` empty). Prepare time differs
only because the second run found compiled models cached.

Priority probe (standalone Swift): a `Task.detached(priority: .utility)`
whose value is awaited from a high-priority task reports `high` for its whole
life; the same task unawaited reports `utility`. The old `stopRecording`
awaited the transcription task from the UI's task, so file ASR, diarization
and enhancement all ran at user-interactive priority.

## Changes

- `AppState.stopRecording` hands the pipeline (`finishMeeting`) to an
  unawaited `Task.detached(priority: .utility)`; callers keep their
  signature and `processingMeetingID` still marks the meeting until the
  pipeline ends. File ASR keeps its own utility detached task.
- `TranscriptionDelivery.batch` (finals only, `.utility`) for the locale
  probes: no volatile decoding, ~10% less recognizer CPU and 40% less wall per
  probe.
- `DiarizationService.diarizerConfig` enables the mask-similarity embedding
  skip (FluidAudio's documented ≤1pp DER tradeoff): −13% CPU, −31% wall,
  identical output on the real meeting.

## Not done, on purpose

- Silence gating for file transcription: measured worse (table above).
- Skipping the second locale probe on a confident first probe: saves ~4 s of
  recognizer CPU per meeting (~3%) for a language-detection heuristic; not
  worth the behavior change.
- FluidAudio runs segmentation and embedding in its own
  `Task.detached(priority: .userInitiated)`; that priority is not
  configurable from the app. Conversion, clustering and reconstruction do run
  at utility now.
- `avconferenced` at 80–107% in the screenshots is not Grañipa: with the app
  idle (0.0% CPU, no audio IO threads in `sample`) it stayed at ~90%.
- `Scripts/bundle.sh` still defaults to a debug bundle; `v2-fixture.sh`
  depends on that. Left unchanged.

## Gates

- `swift build` (debug): exit 0, no warnings, 241.9 s clean build in the worktree.
- `swift test` (debug): 467 tests / 78 suites, exit 0.
- `swift test -c release`: 431 tests / 74 suites, exit 0 (DEBUG-only suites excluded).
- `git diff --check`: clean.
- `./Scripts/bundle.sh release`: `build/Grañipa.app` 27,140 KiB, signed, team R4V252C833,
  still 2.0.1 build 8 — not installed over the running app; that is the human's call.
- Cross-family review: see the PR description.
