# Handoff — Record cuelga (~100–135 % CPU) — 2026-09-04

Para Claude Code (sesión nueva o `granipa-kimi` / `granipa-glm`). Grok no cerró esto: recortes sucesivos, el hang sigue. **No relanzar el loop 20. No commits a `main`. Checkout compartido `feat/dictation-overlay`. Sin worktrees.**

Repo: `~/Dev/02_hq/granipa`
App: `./Scripts/bundle.sh debug` → `build/Grañipa.app` (el binario se llama `Granipa`)
Tests: `swift test` (swift-testing). Último verde: **171 tests / 35 suites**.

## Éxito (medible)

1. Pulsar Record. La UI responde (Stop, menú, ventanas) en el segundo 1.
2. Activity Monitor durante 20 s de silencio: CPU **< 30 %**, **0 Recent hangs**.
3. Stop responde. Tras Stop puede subir CPU (transcribe m4a) — eso está bien.
4. `swift test` verde. Bundle debug + relaunch. Decir el pid nuevo.

No declares done sin (1)+(2) vistos en Activity Monitor. Grok declaró cortes que no bajaron el 100 % en Record.

## Hechos verificados (screenshots del humano)

| Cuándo | pid | CPU | CPU time | Hangs | Notas |
|---|---|---|---|---|---|
| Hang 1 | 70163 | Not Responding | enorme | — | SpeechAnalyzer en MainActor |
| Hang 2 | 42601 | 109 % | 18.29 s | — | 20 threads; probes 2–3 locales × 2 canales |
| Tras recorte 1-locale | (varios) | ~109–126 % | 17–19 s | — | Aún live ASR |
| File-ASR build | **25501** | **134 %** | 25–49 s | **8** | Live ASR ya OFF. 326k ctx switch, 190k faults, 272 MB RSS |
| Tras AEC off + I/O off-thread | **62139** | **103 %** | 19.40 s | — | 12 threads, **0 idle wakeups**. Este es el último fallo |

Pid 62139 = `build/Grañipa.app` con `FileMeetingTranscriber` + AEC forzado off + cola `com.zertyn.granipa.session-write`. **Idle wakeups 0 + ~100 % CPU = un núcleo en userspace sin dormir.** No es un timer.

No hay `sample` del pid en Record: el proceso moría / lo mataban antes. **Primera acción tuya: grabar 10 s y `sample <pid> 5 -file /tmp/granipa-record.sample`.** Sin sample, no adivines el stack.

## Qué ya se hizo (no repetir como si no existiera; sí revertir si está mal)

Live ASR de reunión **apagado** (`MeetingASRPolicy.usesLiveASR` default `false`). Record no llama `TranscriptionCoordinator.start()`. Al Stop: `FileMeetingTranscriber` (un analyzer, `.utility`, sin volatile). Flag `UserDefaults liveMeetingASR` — no lo enciendas.

Captura actual (`RecordingEngine.start` / `RecordingSession`):

- `startMic(echoCancellation: false)` — AEC no se usa aunque Settings tenga el toggle.
- Tap de sistema en `Task.detached`; IO queue qos `.utility`.
- Callbacks: `rmsLevel` + `deepCopy` + `writer.async` (AAC + pad de silencio **fuera** del IO thread).
- `fanOutChunks` false si live ASR off → no hay AsyncStream de PCM hacia Speech.
- Sin `SpeechModels.prewarm` en `AppState.init`.
- UI: MeetingDetail no observa volátiles; captions panel fijo; HUD dice “Transcript after you stop”.

Kimi/GLM informes: `docs/wip/2026-09-03-hang-kimi.md`, `hang-glm.md`, réplicas, `hang-log.md`, `hang-audit.md`.

## Sospechosos que quedan (el sample decide)

1. **`SystemAudioTap` IOProc** (`SystemAudioTap.swift` ~67–72): cada buffer nativo (a menudo 64–256 frames @ 48 kHz = cientos/s) entra a `handleSystem` → `deepCopy` + `vDSP_rmsqv` + `DispatchQueue.async`. Un núcleo de memcpy/malloc sin sleep encaja con 100 % y 0 idle wakeups.
2. **Cola `session-write`**: AAC de esa riada + `appendSilence` en `while` si hay un gap (20 s de silencio de sistema = loop largo). Ya no está en el IOProc; igual puede pegar un core y el proceso se ve “Not Responding” si el main espera `writer.sync` en `stop()`.
3. **`AVAudioEngine` input tap** sin AEC: menos que AEC, no debería ser 100 % solo. Confirmar en sample (`AUVoiceIO` / `vpio` = AEC aún vivo; no debería).
4. **SwiftUI**: `LevelMeter` / HUD / `TimelineView` del timer. Menos probable con 0 idle wakeups.
5. **`FileMeetingTranscriber` / Speech** solo si el humano ya pulsó Stop. El 103 % de 62139 fue **durante** Record.

## Qué hacer (orden)

1. Bundle actual, Record, **sample 5 s**, leer el call graph. El símbolo top es la verdad.
2. Si el top es el tap / `handleSystem` / `deepCopy` / `rmsLevel`:
   - Coalescer a ≥4096 frames **antes** de copiar/escribir.
   - No llamar `rmsLevel` en cada IOProc (cada 100–150 ms basta; `LevelGate` ya está en el hop a UI, no en el RMS).
   - No `deepCopy` por buffer chico: acumular in-place en un buffer preallocatado.
3. Si el top es `AVAudioFile.write` / AAC: no encodees en caliente. Escribe CAF/PCM 16-bit en un ring y transcodifica al Stop, o baja el bitrate y fusiona buffers.
4. Si el top es `appendSilence`: no padees gaps en un `while` síncrono; anota el hueco y padea al Stop, o limita el pad por callback.
5. Si el top es Speech / `SpeechAnalyzer` / `prepareToAnalyze`: algo sigue arrancando live ASR. Grep `coordinator.start`, `transcribeChannel`, `prewarmPreferredLocales`, `ensureInstalled`. No debería correr en Record.
6. Opción nuclear si 2–4 no bastan: **no arrancar el system tap en Record** (solo mic). El audio de “Them” se pierde en live-file; es peor producto pero la app vive. Documenta el tradeoff.

No vuelvas a “un locale”, “Task.detached del tap”, ni “SpeechAnalyzer.priority .medium”. Eso ya está y 62139 igual fue al 103 %.

## Archivos calientes

- `Sources/Granipa/Audio/SystemAudioTap.swift` — IOProc
- `Sources/Granipa/Audio/RecordingSession.swift` — `handleMic`/`handleSystem`/`write*`/`appendSilence`/`writer`
- `Sources/Granipa/Audio/RecordingEngine.swift` — start, AEC false, LevelGate
- `Sources/Granipa/Audio/MicRecorder.swift` — AVAudioEngine tap 4096
- `Sources/Granipa/AppState.swift` — `activateRecording` / `stopRecording`
- `Sources/Granipa/Transcription/FileMeetingTranscriber.swift` — solo post-Stop
- `Sources/Granipa/Transcription/MeetingASRPolicy.swift` — `usesLiveASR` default false

UI (`RecordingHUD`, captions) no es el 100 % de un core con 0 idle wakeups. No empieces por Theme.

## Comandos

```bash
./Scripts/bundle.sh debug
open build/Grañipa.app
pgrep -x Granipa          # el pid a citar
sample <pid> 5 -file /tmp/granipa-record.sample
swift test
```

Ad-hoc sign resetea TCC de audio en cada rebuild; el humano tendrá que re-conceder mic / system audio.

## Prompt corto (pegar a Claude)

```
Repo ~/Dev/02_hq/granipa branch feat/dictation-overlay. Lee docs/wip/2026-09-04-hang-handoff.md entero.

Record cuelga ~100–135% CPU. Último fallo verificado: pid 62139, 103.1% CPU, 19.40s CPU time, 12 threads, 0 idle wakeups, build CON live ASR off + AEC off + AAC fuera del IO thread. 8 hangs en el pid 25501 (mismo síntoma, live ASR ya off).

NO repitas los recortes de SpeechAnalyzer/MainActor/locales. El hang que queda es captura de audio. Primera acción: bundle, Record 10s, sample del pid, lee el stack, arregla lo que el sample diga.

Éxito: Record 20s silencio, UI viva, CPU <30%, 0 Recent hangs, swift test verde, bundle debug, pid nuevo.

No commits a main. No worktrees. No loop 20.
```
