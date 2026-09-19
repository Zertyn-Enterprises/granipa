# GLM hallazgos arch/perf/ASR — 2026-09-03

Fase 1, solo lectura. Todo lo no marcado "inferencia" fue leído en el código o
ejecutado esta sesión. Árbol: `main` @ bd05f9d. Pin FluidAudio verificado en
`.build/workspace-state.json`: rev `7f963cdc43ba89c5993654f1e138047d517a818d`, versión **0.15.2** — el árbol de `.build/checkouts/fluidaudio` ES 0.15.2 (el git del checkout está roto por un path alterno con "ñ"; workspace-state es la fuente fiable).

## Perfil de recursos (verificado)

App idle pid 28248: **93.840 KB RSS, 0.0% CPU**, ~14 min elapsed (`ps`). Bundle
`build/Grañipa.app` = **21 MB** (binario 16 MB, GRDB+FluidAudio enlazados estáticos, Sparkle 3 MB).

Loops siempre-on con la app abierta (confirmados en código):

| Loop | Intervalo | Dónde corre | Trabajo por tick |
|---|---|---|---|
| ClipboardMonitor | 700 ms | **MainActor** | changeCount + UserDefaults (`ClipboardMonitor.swift:16-22,29-37`) |
| MeetingDetector | 5 s | **MainActor** | CoreAudio síncrono: process list + 2 props por proceso (`MeetingDetector.swift:37-42,56-101`) |
| WebhookService.deliverDue | 30 s | Task | SELECT a SQLite aunque no haya webhooks (`AppState.swift:199-205`) |
| CalendarService.refresh | 300 s | MainActor | EKEventStore fetch (`CalendarService.swift:46-52`) |
| Sparkle updater | default (24 h) | propio | `UpdaterManager.swift:21-22` |

Solo durante grabación: watchForDeadChannels 5 s (`RecordingEngine.swift:66`),
meetingEndWatch 5 s (`AppState.swift:104-127`), TimelineView 1 s en HUD/Bar
(`RecordingHUD.swift:43,95`, `RecordingBar.swift:19` — solo si la vista está visible), y el pipeline de audio/transcripción.

## Correcciones a los "hechos verificados" de Grok

1. **"Streaming ASR puede no existir en 0.15.2" — falso.** El árbol 0.15.2
   contiene y exporta streaming público:
   - `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift` — actor público, `appendAudio(AVAudioPCMBuffer)`, callbacks EOU/parcial, chunks 160/320/1280 ms (en, 120M).
   - `ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift` — streaming multilingüe (9 idiomas según comentario en `ModelNames.swift:36-41`).
   - `ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift` — TDT con `streamAudio(buffer)` + `AsyncStream` de updates + `finish()`.
2. **"¿Se descarga ~130 MB cada vez?" — no.** Cache en disco en
   `~/Library/Application Support/FluidAudio/Models/` (`DownloadUtils.swift:224`); en esta máquina el diarizer ocupa **21 MB** (medido con `du`). `prepareModels()` solo descarga si falta (`OfflineDiarizerManager.swift:52-89`, guarda `fileExists` en `DownloadUtils.swift:275,308`). Sí re-carga y pre-calienta los MLModel en cada reunión (ver P2-4).
3. Confirmo lo demás de Grok: pin+link de FluidAudio en `Package.swift:11,26` (CLAUDE.md miente); 6 analyzers en auto (`LanguageDetection.swift:33` cap 3, default 2 en `:32`); 8 tabs / 607 líneas en Settings (`SettingsView.swift:7-23`); loops 700 ms/5 s/30 s; API :7799 default on (`AppState.swift:183-197`).
4. **CLAUDE.md miente en un punto más**: dice migraciones v1..v3; hay **v1..v7** (`AppDatabase.swift:27-123`). Y omite toda la superficie productivity (clipboard/OCR/window-snapping).

## Hallazgos

### P0-1 — Sustituir el ASR live por Whisper local OSS empeora el objetivo de recursos

- evidencia: motor live actual = SpeechAnalyzer streaming on-device, 2 instancias por locale (`ChannelTranscriber.swift:22-34`), 0 MB de modelos en el bundle (los gestiona macOS), volatile results para live (`ChannelTranscriber.swift:26`). Whisper local = 75 MB–3 GB residentes y por chunks, no streaming real (hecho verificado por Grok); el "unload a los N segundos" de SuperWhisper existe precisamente porque el coste en RAM no se sostiene.
- coste ahora: 0. El dolor real de recursos está en el arranque de grabación (P1-2) y en los loops idle (P1-3..5), no en el motor ASR.
- arreglo mínimo: ninguno al motor live. La vía OSS local cabe en post-proceso (opción D de la tabla) donde el pico de RAM se paga al parar y se libera al terminar.
- riesgo de no tocarlo: ninguno. Riesgo de tocarlo: 150 MB–3 GB de RAM caliente, nueva dependencia, pérdida de 15+ idiomas y de volatile results.

### P1-2 — Auto-language: hasta 6 SpeechAnalyzer + 6 transcripciones del mismo audio hasta decidir

- evidencia: `TranscriptionCoordinator.start()` lanza `locales × 2 canales` transcribers (`TranscriptionCoordinator.swift:45-67,91-119`); cada uno crea su SpeechTranscriber+SpeechAnalyzer+converter (`ChannelTranscriber.swift:22-34`). La decisión exige ≥40 chars de texto (`LanguageDetection.swift:54`) o el force al parar. Default `probeLocales` = en-US + es-ES (`LanguageDetection.swift:32`), cap 3 (`:33`).
- coste ahora: mientras no se decidan (típicamente los primeros 10-30 s de habla), 2 locales → 4 analyzers corriendo ASR sobre el mismo audio (3 locales → 6), 3× conversión de formato por canal (`startChannel` fan-out `:104-113`), y cada volatile de cada analyzer hace hop al MainActor (`TranscriptionCoordinator.swift:126-129`) → tormenta de invalidaciones SwiftUI en el HUD. Además `SpeechModels.ensureInstalled` corre **serial y antes de .live**: en primera grabación descarga assets de Apple por red, sin timeout, en el hot path (`TranscriptionCoordinator.swift:52-60`, `SpeechModels.swift:36-45`).
- arreglo mínimo: (a) precalentar assets de speech en idle tras el launch, no al grabar; (b) default de probes a 1 locale (el cross-vote de `LanguageDetection.decide` solo aporta con ≥2, pero NLLanguageRecognizer sobre los primeros finals ya da una señal gratuita); (c) decidir al primer final en vez de esperar 40 chars. Son cambios de política, no de arquitectura.
- riesgo de no tocarlo: arranque de grabación 2-3× más caro en CPU/energía y UI que tiemble durante la fase probe.

### P1-3 — Medidor de niveles: un Task al MainActor por buffer de audio

- evidencia: `RecordingEngine.start` instala `onLevel` que hace `Task { @MainActor … }` por buffer (`RecordingEngine.swift:24-32`); el mic entrega cada 4096 frames (~12/s a 48 kHz, `MicRecorder.swift:30`); el system tap entrega por ciclo de IO (típicamente más frecuente; inferencia) → decenas de hops/s a main mientras suena audio. Cada hop muta `micLevel`/`systemLevel` en un `@Observable` → invalidación de HUD/RecordingBar/MenuBarExtra; `ActivityDot` anima por cambio de nivel (`RecordingHUD.swift:180-189`).
- coste ahora: bajo en CPU absoluto pero constante durante toda grabación; es el patrón "timer por frame" que SwiftUI no pide.
- arreglo mínimo: throttle en el callback (emitir a main máx. cada ~100 ms o solo si Δnivel > umbral). ~10 líneas.
- riesgo de no tocarlo: energía en grabación larga; margen para jank del HUD.

### P1-4 — ClipboardMonitor: poll 700 ms en MainActor, para siempre, aunque esté desactivado

- evidencia: se arranca incondicional al init (`AppState.swift:58-63`); el loop duerme 700 ms y hace `poll()` en MainActor (`ClipboardMonitor.swift:16-22`); `isEnabled` solo se consulta DESPUÉS de detectar cambio (`:37`) — el timer y el UserDefaults-read corren aunque el usuario lo tenga apagado. ~5.100 wakeups/h de main.
- coste ahora: idle wakeups + trabajo en el hilo de UI.
- arreglo mínimo: consultar `isEnabled` para no arrancar el task (y observarlo si se cambia el setting), y/o subir a 2 s. No hay API de eventos de pasteboard pública; el intervalo es el techo.
- riesgo de no tocarlo: contribuye a "menos recursos" sin ganancia funcional para quien no usa clipboard history.

### P1-5 — MeetingDetector: CoreAudio síncrono en MainActor cada 5 s, default on

- evidencia: clase `@MainActor`, `poll()` en el Task (`MeetingDetector.swift:37-42,56-57`) llama a `audioCaptureProcesses()`: `AudioObjectGetPropertyDataSize` + `GetPropertyData` + por proceso `kAudioProcessPropertyBundleID` e `IsRunningInput`, todo síncrono en main (`:78-101`). Default `meetingDetectionEnabled ?? true` (`AppState.swift:156-159`).
- coste ahora: 720 rondas/h de IPC a CoreAudio en el hilo de UI. Barato pero evitable; y con muchos procesos de audio el tick crece.
- arreglo mínimo: hop a fondo (`nonisolated` ya son los helpers) y volver a main solo para escribir estado; o listener de `kAudioHardwarePropertyProcessObjectList` (misma familia de API que ya usan en `RecordingSession.swift:73-98` para device changes).
- riesgo de no tocarlo: main actor hace I/O de sistema periódico; latencia pico si CoreAudio tarda.

### P1-6 — Búsqueda: SELECT LIKE sobre todo el corpus por pulsación de tecla, en MainActor, sin debounce

- evidencia: `HomeView.onChange(of: searchQuery)` llama síncrono a `db.searchMeetings` (`HomeView.swift:96-102`), que hace `LIKE` sobre 5 columnas de meeting LEFT JOIN transcriptSegment sin índice FTS (`AppDatabase.swift:297-318`).
- coste ahora: con pocos meetings, nada; con cientos de reuniones transcritas (miles de segmentos), stall de main por tecla.
- arreglo mínimo: debounce 200 ms + `Task.detached` para la query; FTS5 solo si el corpus crece.
- riesgo de no tocarlo: degradación percibida conforme se usa el producto (que graba transcripts a propósito).

### P2-1 — Webhook loop: SELECT cada 30 s con cero webhooks configurados

- evidencia: `AppState.startServices` lanza el loop siempre (`AppState.swift:199-205`); `deliverDue` abre read transaction (`WebhookService.swift:25-27`, `AppDatabase.swift:246-261`). 120 lecturas/h idle.
- arreglo mínimo: `guard !webhooks.isEmpty` (ya están en memoria en `AppState.webhooks`).
- riesgo: menor; es ruido de wakeups/IO.

### P2-2 — API server default ON

- evidencia: `apiEnabled ?? true` (`AppState.swift:183`); listener TCP :7799 solo loopback IPv4 (`APIServer.swift:16-18`) + bearer token generado (`AppState.swift:169-179`); auth testeada (`APITests.swift:52`, integración TCP real `APIServerIntegrationTests.swift:8`). Una DispatchQueue nueva por conexión (`APIServer.swift:47`) — irrelevante con tráfico local esporádico.
- arreglo mínimo: default off. Es superficie de ataque y una feature de integración minoritaria; el coste idle del listener es ~0, así que esto es higiene, no perf.
- riesgo de no tocarlo: puerto local escuchando y token persistido en UserDefaults para todo usuario aunque no use la API.

### P2-3 — Diarization: manager y modelos recargados por reunión

- evidencia: `DiarizationService.diarize` crea `OfflineDiarizerManager()` nuevo y `prepareModels()` cada postProcess (`DiarizationService.swift:42-45`); con `models == nil` recarga los 4 MLModel del disco y pre-calienta ANE (`OfflineDiarizerManager.swift:34-37,415-435`). NO re-descarga (cache 21 MB verificada; descarga solo si falta o si el load falla → purge+download `:60-88`).
- coste ahora: segundos de load+prewarm en cada post-proceso; RAM liberada al terminar (manager local) — patrón unload correcto ya de facto.
- arreglo mínimo: manager estático de larga vida si el load mide >1 s en la práctica; medir antes de tocar.
- riesgo de no tocarlo: post-proceso más lento de lo necesario.

### P2-4 — AppState god object (536 líneas)

- evidencia: mezcla orquestación de grabación (`:264-324`), postProceso+enhance (`:326-428`), CRUD de 4 entidades (`:430-535`), ciclo de vida de 5 servicios (`:181-214`), y estado de UI (`:24-27`). Además dos inits (`:34`, `:216`) — el segundo solo para… nada visible en producción (sospechoso; inferencia: legado de tests).
- qué extraer si se toca: `RecordingFlow` (start/stop/postProcess/enhance) y `MeetingStore` (CRUD). Qué dejar: lo demás. No proponer más capas.
- riesgo de no tocarlo: cada feature nueva engorda el MainActor que también renderiza UI. No es urgente; la extracción sin tests del flujo (ver P2-5) es más riesgosa que el desorden actual.

### P2-5 — Tests: huecos en el corazón del producto

- verificado cubierto (bien): API token auth + TCP real (`APITests`, `APIServerIntegrationTests`), HMAC de webhooks + backoff (`APITests.swift:109-140`), DB round-trips/cascadas/search/reemplazo por canal con GRDB real (`AppDatabaseTests`), subprocess LLM real con timeout/deadlock (`LLMTests.swift:7-46`), lógica pura de idiomas/diarización/exporter.
- huecos 🔴/🟡: **TranscriptionCoordinator** (probe→adopt→pendingFinals→pump: cero tests; la lógica más enrevesada del producto, `TranscriptionCoordinator.swift:91-260`), **RecordingSession** padding de silencio/gap 0.25 s (`RecordingSession.swift:234-250`), **WebhookService.deliverDue** máquina de reintentos (solo backoff unit-testeado), **AppState.postProcess/enhance** flujo, **DiarizationService**.
- coste de cubrirlos: coordinator y webhook-loop son testeables con streams/DB en memoria sin hardware; recording-session necesita buffers sintéticos de AVAudioPCMBuffer (factible, ver `AudioHelpersTests`).
- riesgo de no tocarlos: cualquier refactor (P2-4, o tocar el pipeline ASR) va sin red.

### P2-6 — Detalles Swift 6 / hilos

- Device-change listeners en `DispatchQueue.main` (`RecordingSession.swift:83,97`) → `restartSystemTap`/`restartMic` (CoreAudio síncrono) corren en main al cambiar de AirPods mid-meeting. Raro pero es un hitch de UI en el peor momento. Mover a una queue propia.
- `Task { @MainActor self.apply(update) }` sin estructurar por volatile (`TranscriptionCoordinator.swift:126-129`) — ver P1-2.
- `AsyncStream` sin buffering policy explícito en el fan-out (`TranscriptionCoordinator.swift:97`): default unbounded; con 6 consumidores lentos la cola crece. Bajo riesgo real (los analyzers consumen), pero conviene `.bufferingNewest` si se toca.

## ASR: tabla A/B/C/D (hechos vs inferencia)

| | A. SpeechAnalyzer (actual) | B. FluidAudio Parakeet/Nemotron (pin 0.15.2) | C. whisper.cpp / WhisperKit | D. Híbrido A + OSS batch al parar |
|---|---|---|---|---|
| Estado | **Verificado en código**: streaming on-device, volatile, 2 canales, 0 deps nuevas | **API verificada en 0.15.2**: `StreamingEouAsrManager` (en, 120M, 160-1280 ms), `StreamingNemotronMultilingualAsrManager` (streaming multi, 9 langs según código), `SlidingWindowAsrManager` (TDT). **No hace falta bump para probar streaming** | No probado en el repo; datos de Grok verificados externamente | Diarización batch de FluidAudio **ya integrada** (`DiarizationService.swift:42-45`); falta el ASR batch |
| RAM idle | 0 extra (modelos del SO; app idle 92 MB medido) | Modelos no cargados hasta uso → 0 idle extra | 0 si se descarga; el patrón SW es unload a N s | 0 idle extra |
| RAM grabando | 2 analyzers (o 2N en probe; P1-2). *Inferencia: cientos de MB gestionados por el SO, no medido* | *Inferencia no medida*: EOU 120M ≈ 250 MB fp16; Nemotron/TDT 0.6B ≈ 600 MB-1.2 GB según cuantización | 150 MB–3 GB mientras caliente (hecho Grok) | A + pico batch al parar, liberado al terminar |
| Chip | *Inferencia (docs Apple): ANE* | **Docs actuales**: ANE, CPU/GPU libres; TDT 210× RTFx, EOU 12× RTFx (M4 Pro) | CPU/GPU (whisper.cpp) o CoreML (WhisperKit) | A (live) + ANE (batch) |
| Latencia percibida | Volatile results → sub-segundo (verificado `reportingOptions .volatileResults, .fastResults`) | EOU: streaming real con EOU detection (API verificada); TDT sliding: ventana de ~15 s → semi-live | Por chunks: 1-5 s de retraso típico | Live = A; batch al parar añade segundos-minutos al post |
| Idiomas | `SpeechTranscriber.supportedLocales` (25+; *inferencia* el número exacto) | EOU en-only; Nemotron multi 9 (código); TDT 25 (docs) — **es crítico para un usuario hispanohablante: la vía B streaming liviana es en-only; la multi es 0.6B** | ~100 langs según modelo | A live + el del modelo batch |
| Trabajo de integración | 0 | Medio: `AudioChunk.buffer` ya es AVAudioPCMBuffer → `appendAudio`/`streamAudio` directo; lifecycle de modelos + política de unload + sustituir coordinator. Días, no semanas. Dep ya en el grafo y bundle | Alto: dependencia nueva, gestión de modelos, VAD, chunking, UI de descargas — re-implementar el stack de SuperWhisper | Bajo-medio: ya está postProcess; añadir TDT batch sobre los m4a existentes |
| Riesgo bundle/deps | Ninguno | Bundle igual (21 MB; modelos van a Application Support por HF download — **red en primer uso y disco 120 MB-1.2 GB**). Pin exact ya sufre renames breaking en minors (`Package.swift:10` comentario) | Dependencia nueva pesada + modelos | Igual que B pero sin tocar el hot path |
| Veredicto para "live tipo SuperWhisper y mínimos recursos" | **Cumple ambas hoy**. El gap es calidad/atribución, no latencia ni recursos | Streaming real solo en (en) liviano; multi = 0.6B. Cambio de motor no recomendado para live | **Contradice "mínimos recursos"** — P0-1 | **Camino recomendado**: satisface "OSS local" sin tocar el live |

## Recortes (qué apagar / unload / fusionar)

1. **API server default off** (`AppState.swift:183`). Superficie, no perf. ~1 línea.
2. **Clipboard monitor**: no arrancar si disabled + intervalo 2 s (`ClipboardMonitor.swift:14-22,29-31`).
3. **Detector**: sacar CoreAudio de main y/o listener de eventos (`MeetingDetector.swift:37-42`).
4. **Webhook loop guard** `webhooks.isEmpty` (`AppState.swift:199-205`). 1 línea.
5. **Probes**: default 1 locale + precalentamiento de assets en idle (P1-2).
6. **Niveles con throttle** (P1-3). ~10 líneas.
7. **Window snapping + OCR + clipboard** (~1.100 líneas: WindowManager 132, WindowLayout 56, PasteService 37, OCRService 71, Clipboard/* ~700): coste idle ~0 — **no es un problema de recursos, es de foco de producto**. Recortarlos es decisión de producto del humano (¿meeting-notes o utilities bundle?), no una optimización. No los mezclar con este plan de perf.
8. **Unload de modelos**: hoy no hace falta (SpeechAnalyzer gestiona el SO; el diarizer ya se libera al terminar el post-proceso). La política de unload tipo SuperWhisper solo becomes real si se adopta B/D con modelos propios.

## Réplica pendiente / hecha

Kimi dejó `docs/wip/2026-09-03-kimi-hallazgos.md` (mensaje recibido). Este
informe se escribió sin leerlo. Réplica en `docs/wip/2026-09-03-glm-replica.md` — a continuación.
