# Hang / CPU — auditoría adversarial Record

Grok orquesta. Checkout compartido `feat/dictation-overlay`. **Sin worktrees. Sin commits. No tocar `main`.** No relanzar el loop 20.

El humano: Record se cuelga (Not Responding) y come CPU. Si hay que refactorizar para ser eficientes, se refactoriza.

## Hechos verificados (no redescubrir; sí contradecir si el código actual dice otra cosa)

Tres colgados en esta sesión:

1. pid 70163 Not Responding, recursos enormes. Causa: `SpeechTranscriber` / `prepareToAnalyze` / `ensureInstalled` en el MainActor.
2. pid 42601, 109.2 % CPU, 18.29 s CPU, 20 threads, colgado otra vez. Causa: 2–3 probe locales × mic+system = hasta 6 `SpeechAnalyzer`, más `.fastResults`.
3. Tras el recorte (1 locale, `Task.detached`, sin `.fastResults`, captions debounce 250 ms) **el usuario mandó otra captura: se volvió a colgar.** Ese recorte no bastó.

Grok acaba de aterrizar un tercer recorte (en el árbol ahora, bundle debug, app idle pid 57234 ~0.4 % CPU — **no pulses Record** en esa instancia, es la del humano):

- `LanguageDetection.startLocales` → 1 locale.
- `SpeechAnalyzer.Options(priority: .medium, modelRetention: .lingering)`.
- Mic `prepareToAnalyze` primero; system espera a `onReady` (`startLiveChannels`).
- Volátiles fuera del MainActor (`VolatileMailbox`, flush 80 ms).
- Tap de sistema en `Task.detached`; mic AEC sigue en main tras un `Task.yield`.
- `isStarting` para no reentrar.
- MeetingDetail ya no hace `scrollTo` en cada volátil.

**Idle está bien. Record no está verificado.** El colgado 3 ocurrió con 1 locale × 2 canales. El sospechoso que queda es **dos `SpeechAnalyzer` live + AEC en main + tres árboles SwiftUI observando el coordinator.**

## Objetivo

Record: la UI responde en el clic (Stop, menú, ventanas). CPU live << 100 % en silencio. Un núcleo al 100 % durante `prepareToAnalyze` está mal si el main no procesa eventos.

Producto: captions live de Me **y** Them si se puede sin colgar. Si no se puede, mic live + Them desde el m4a al parar es aceptable — **decídelo en el informe con el tradeoff, y si está en tu slice, impleméntalo.** Audio a fichero no se toca (mic.m4a + system.m4a siguen igual).

## Dueños — no pisar

| Quién | Ficheros | Qué atacar |
|---|---|---|
| **Kimi** | `UI/MeetingDetailView.swift`, `UI/RecordingHUD.swift`, `UI/RecordingBar.swift`, `UI/CaptionsOverlay*.swift`, `UI/HomeView.swift`, `UI/SidebarView.swift`, `UI/MenuBarView.swift`, `UI/MainWindow.swift` | Observación SwiftUI. Tres superficies (HUD + captions + transcript) leen `volatileMic/System` + `liveSegments`. `LevelMeter` anima cada 150 ms. `pipelinePhase` lee `transcription?.phase` por meeting. `CaptionsOverlayController.fittingSize`. **No toques `Transcription/`, `Audio/`, `AppState.swift`.** |
| **GLM** | `Transcription/ChannelTranscriber.swift`, `Transcription/TranscriptionCoordinator.swift`, `Transcription/SpeechModels.swift`, `Transcription/MeetingASRPolicy.swift`, `Transcription/LanguageDetection.swift`, tests de eso | Dos analyzers live. `transcribeChannel` mete **cada** buffer (incluido silencio). `ensureInstalled` fabrica un `SpeechTranscriber` para pedir assets. `prewarmPreferredLocales` instala **todos** los probes al launch. `database.save` de finals en MainActor. `String(result.text.characters)` por volátil. System ASR arranca aunque no haya audio de sistema. **No toques `UI/*`, `AppState.swift`, `RecordingEngine.swift`.** |
| **Grok** | `AppState.swift`, `Audio/RecordingEngine.swift`, `Audio/RecordingSession.swift`, `Dictation/DictationController.swift` | AEC en main, tap off-main (ya), delay de prewarm, LevelGate del waveform de dictado. |

Si necesitas un fichero ajeno: escríbelo en tu informe, no lo edites.

## Hipótesis a verificar (código + docs Apple, no “probablemente”)

1. Dos `SpeechAnalyzer` simultáneos (mismo locale, dos streams) superan el límite de analyses o saturan ANE → main no pinta. Docs: “Manage simultaneous analyses” en SpeechAnalyzer.
2. `SpeechAnalyzer` es `actor`; `prepareToAnalyze` a `.userInitiated` por defecto come el núcleo que el MainActor necesita. Ya bajamos a `.medium` — ¿hace falta `.utility`? ¿un analyzer solo?
3. Meter silencio en el transcriber cuesta igual que habla. `SpeechDetector` como módulo **no** ahorra si el transcriber sigue recibiendo audio — hay que no hacer `yield` de silencio (con hangover) o no crear el analyzer de system hasta `systemNonSilentCount > 0`.
4. `@Observable TranscriptionCoordinator` en `AppState.transcription`: cualquier vista que haga `if let live = app.transcription` y luego lea volátiles se invalida a 12 Hz. MeetingDetail re-layouta el `ForEach` de segmentos.
5. `AVAudioEngine` + voice processing en main (tras yield) sigue siendo un hitch de segundos. Grok lo tiene; no lo dupliquéis.
6. `handleMic`/`handleSystem`: AAC write + `deepCopy` + fan + convert en el hilo de IO. No es main, pero dos converters Speech a 48 kHz stereo suman.

## Entregables (en este orden)

1. Informe **antes** de un refactor grande.
   - Kimi → `docs/wip/2026-09-03-hang-kimi.md`
   - GLM → `docs/wip/2026-09-03-hang-glm.md`
   Formato: Verificado vs inferencia. Cada hallazgo: `archivo:línea`, P0/P1/P2, arreglo, riesgo de no tocarlo.
2. Luego implementáis en VUESTROS ficheros el arreglo más barato que quite el colgado.
3. `swift build` (si `input file modified`, esperar y reintentar — checkout compartido).
4. Una línea append en `docs/wip/2026-09-03-hang-log.md`.
5. **No** `swift test` completo en paralelo (Grok lo corre). Tests del slice sí.
6. Réplica del informe del otro cuando exista: `docs/wip/2026-09-03-hang-kimi-replica.md` / `hang-glm-replica.md`.

## Arreglos candidatos (elegid, no implementéis los tres)

- **A (P0 CPU):** 1 `SpeechAnalyzer` live (mic). System se transcribe del m4a al `stop` (fuera de main). Them live desaparece durante la reunión; el transcript final está completo.
- **B (P0 CPU, menos producto):** no arrancar system ASR hasta el primer buffer no silencioso; 1 analyzer en “Quick note” / sala vacía.
- **C (P1 UI):** MeetingDetail no observa volátiles; HUD+captions sí. Overlay tamaño fijo, cero `fittingSize`.
- **D (P1 ASR):** no alimentar silencio al analyzer (hangover ~400 ms). Medir que los timestamps de segmento siguen siendo meeting-relative.
- **E (P2 launch):** `prewarmPreferredLocales` solo `lastSpeechLocale` o 1 id, no la lista de probes.

Kimi: C es tuyo. GLM: A/B/D/E son tuyos. Si eliges A, documenta el tradeoff Them-live en el informe **y** el punto de enganche para transcribir el system m4a (Grok cablea `AppState.stopRecording` si el hook queda claro).

## Prohibido

- Pulsar Record / dictar / matar pid 57234.
- Relanzar el loop 20 / scheduler.
- Commits, `main`, worktrees, `CONTEXT.md`.
- Editar ficheros del otro.
- Debilitar tests para ponerlos verdes.
