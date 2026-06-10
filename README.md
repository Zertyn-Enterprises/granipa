# Grañipa

A native macOS meeting notes app — a personal, self-hosted replacement for Granola.
Records your meetings (mic + system audio, no bot joins the call), transcribes them
live on-device, identifies who said what, enhances your rough notes with AI, and
pushes everything to your own services.

Everything runs locally and free:

- **Transcription**: Apple SpeechAnalyzer (macOS 26, on-device, English & Spanish).
- **Speaker diarization**: FluidAudio CoreML models, local (optional, see below).
- **AI notes**: your existing CLI subscriptions (`claude`, `codex`, `gemini`, `grok`) —
  no API keys, no per-token billing.

## Requirements

- macOS 26+ (Apple Silicon), Xcode 26 toolchain to build.
- At least one of the LLM CLIs installed and logged in: `claude`, `codex`, `gemini`, `grok`.

## Build & run

```sh
./Scripts/bundle.sh            # debug build -> build/Grañipa.app
./Scripts/bundle.sh release    # optimized build
open "build/Grañipa.app"
```

Signing: the script picks your first Apple Development certificate automatically
(set `CODESIGN_ID` to override). If the keychain blocks signing it falls back to
ad-hoc — that works, but macOS forgets the audio permissions on every rebuild,
so approving codesign keychain access once is worth it.

### First-run permissions

macOS will prompt for, in roughly this order:

1. **Microphone** — your channel ("Me").
2. **System Audio Recording** — the other participants ("Them"). Appears the
   first time you start a recording; check *System Settings → Privacy & Security →
   Screen & System Audio Recording* if you miss it. If denied, recordings are
   silently mic-only.
3. **Calendars** — upcoming meetings in the sidebar (works with Google accounts
   already added to macOS Calendar).
4. **Notifications** — "meeting detected, record?" prompts.
5. On the first recording per language, the speech model downloads once.

## Enabling speaker diarization

Diarization (Speaker 1/2/3 + AI name inference) needs the FluidAudio package.
Uncomment the two lines referenced in `Package.swift` (dependency + product),
then `swift build` — first run downloads ~130 MB of CoreML models from
HuggingFace, after which it is fully offline. Without it the app still works,
labeling remote speech as "Them".

## REST API

Local-only server on `127.0.0.1:7799` (configurable in Settings → API, where the
bearer token lives):

```sh
TOKEN=...   # Settings -> API -> Copy
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings/<id>/transcript
curl -X POST -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings/<id>/enhance
```

## Webhooks

Settings → Webhooks. Events: `meeting.started`, `meeting.completed` (includes the
full transcript), `notes.enhanced`. Deliveries retry with backoff (5 attempts).
Each POST is signed; verify like GitHub-style HMAC:

```python
import hmac, hashlib
expected = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
valid = hmac.compare_digest(expected, request.headers["X-Granipa-Signature"])
```

## Development

```sh
swift build    # compile
swift test     # unit + integration tests
```

Data lives in `~/Library/Application Support/Granipa/` (SQLite + per-meeting audio).
