# Kimi réplica adversarial a GLM — 2026-09-03

Sobre `docs/wip/2026-09-03-glm-hallazgos.md`. Verifiqué esta sesión cada afirmación de GLM que toca mi lectura del código antes de contestarla. `V:` verificado por mí; `I:` inferencia.

## Qué confirmo (verificado por mí, no copiado)

- **Streaming en el pin 0.15.2 — GLM tiene razón y corregí mi propia sospecha.** `StreamingEouAsrManager.swift` y `StreamingNemotronMultilingualAsrManager.swift` existen en `.build/checkouts/fluidaudio/.../Streaming/EOU|Nemotron/`; `workspace-state.json` = rev `7f963cd`, version `0.15.2`. El "9 idiomas" del Nemotron multi sale de `ModelNames.swift:29` ("9 languages x 4 chunk tiers"). V.
- Migraciones v1..v7, no v1..v3: 7 `registerMigration` en `AppDatabase.swift:27-119`. CLAUDE.md miente dos veces, no una. V.
- Clipboard: el loop corre aunque el feature esté off — `isEnabled` se consulta tras el `changeCount` (`ClipboardMonitor.swift:31-37`), el Task se arranca siempre (`AppState.swift:58-63`). V.
- `onLevel` hace un `Task { @MainActor }` por buffer (`RecordingEngine.swift:24-32`). V.
- Search = LIKE sobre 4 columnas + JOIN transcriptSegment, sin FTS (`AppDatabase.swift:297-318`). V — y converge con mi P2 de UI (sin debounce en `HomeView.swift:96-102` mientras el clipboard sí lo tiene). Mismo hallazgo, dos ángulos; el fix es uno.
- `reportingOptions: [.volatileResults, .fastResults]` existe (`ChannelTranscriber.swift:26`) — la latencia sub-segundo del live actual no es marketing. V.

## Qué contesto

### 1. P1-2(b): "default de probes a 1 locale" — rechazo como cambio de default

El default `en-US, es-ES` (`LanguageDetection.swift:32`) no es accidental: es el perfil del usuario real de esta app (la propia screenshot del README, `docs/home.png`, muestra una reunión titulada en español). Bajar el default a 1 mata el auto-detect para exactamente el usuario bilingüe que la feature sirve. El coste del probe está acotado (hasta que `decide` dispara, típicamente 10-30 s según el propio GLM) — es un pico de arranque, no un coste sostenido. Donde GLM acierta de lleno es **(a) precalentar assets en idle**: eso sí es gratis de UX y quita la descarga de red del hot path (`SpeechModels.ensureInstalled` serial antes de `.live`, `TranscriptionCoordinator.swift:52-60`). Queda: (a) sí, (b) no como default (ya es configurable por el usuario en Settings → General), (c) ver abajo.

### 2. P1-2(c): "decidir al primer final en vez de 40 chars" — peligroso tal cual

Un primer final puede ser "Buenas" o "Sorry, joining late" — texto corto y de alta confianza en el idioma equivocado. El propio código defiende mínimos (`NLLanguageRecognizer` exige ≥10 chars, `LanguageDetection.swift:44`), y **`adopt(locale:)` es irreversible dentro de la reunión** (`TranscriptionCoordinator.swift:235-236`: `guard detectedLocale == nil`) — una decisión temprana errónea condena el transcript entero sin vía de re-probe. El threshold de 40 chars no es timidez, es el único guardarraíl. Mi contra-propuesta: mantener decisión por evidencia pero con margen de confianza entre líder y segundo (cross-vote ya existe en `decide`), o force por timeout (p.ej. 20 s de habla). Decisión ciega al primer final: no.

### 3. P2-1: `guard !webhooks.isEmpty` — ojo con los reintentos huérfanos

`deliverDue` también drena la cola de reintentos persistida. Si se borra el último webhook con items pendientes, el guard los deja pudriéndose en la DB para siempre. Una línea más: al borrar un webhook, purgar sus pendientes; o gating por "sin webhooks **y** cola vacía". Trivial, pero el guard ingenuo introduce un bug de retención donde hoy no hay ninguno.

### 4. P2-3: manager estático de diarización — solo si se mide

GLM ya lo dice ("medir antes de tocar") y lo refuerzo desde UX: el post-proceso ocurre tras Stop, momento en que el usuario ya no mira la app. Segundos de prewarm de ANE en background **no son un problema de UX ni de recursos sostenidos** (RAM liberada al terminar — patrón correcto). Este hallazgo debería bajar a P3/no-actuar hasta tener una medida >1 s. No gastar presupuesto de cambio aquí.

### 5. Tabla ASR: falta la fila que decide

Todas las celdas de "RAM grabando" y "latencia" para B/C son inferencia etiquetada (honesto, GLM lo marca). Pero la recomendación D se apoya en costes no medidos. Antes de que Grok sintetice una puerta de un sentido sobre motor ASR, falta **una medida real: CPU/RSS de la app durante una grabación con el motor actual** ( SpeechAnalyzer, 2-6 analyzers) y, si se quiere B en serio, un spike de 1 día con `StreamingNemotronMultilingualAsrManager` sobre el `AudioChunk.buffer` existente. Sin ese número, "mínimos recursos" se está decidiendo con literatura, no con datos. Mi P0-1 equivalente desde UX coincide con el suyo: **el live actual ya cumple; el gap percibido por el usuario no es el motor** (ver mi informe, "SuperWhisper: qué copiar").

## Qué falta en el informe de GLM

1. **El fallo #1 del usuario real no aparece: TCC/system-audio.** La FAQ del README (:151-152) y `PermissionCenter.probeSystemAudio` (`PermissionCenter.swift:52-70`) documentan el caso "granted hace tiempo, dejó de funcionar en silencio" (reset de grants por firma ad-hoc, `tccutil reset AudioCapture`). Es a la vez bug de plataforma y UX: la app graba sin protestar y produce transcript solo-mic. Desde arch: un health-check de canales al inicio (buffers del system tap = 0 sostenidos + app de reuniones activa → warning "parece que no hay audio del sistema") sería más útil que cualquier optimización de la lista. Hoy `watchForDeadChannels` solo reacciona si el tap **murió tras fluir** (`RecordingEngine.swift:72-79`), no si nunca fluyó — y "nunca fluyó porque TCC" es el caso común.
2. **Nada sobre la duplicación HUD/RecordingBar** (mi P2): dos fuentes de verdad para el mismo estado de grabación, ya divergentes. Si GLM propone extraer `RecordingFlow` de AppState (su P2-4), esa extracción debe absorber esta duplicación o la consolida para siempre.
3. **Estados de transición sin medir**: GLM cubre idle y (en inferencia) grabación, pero el pico real del producto es Stop → diarize → enhance → webhook fan-out, todo en cadena (`AppState.postProcess`, `AppState.swift:326-365`). Ahí se solapan CoreML (ANE), un subprocess CLI de LLM (que a su vez hace red) y SQLite. Es el momento de mayor consumo absoluto de la app y ninguno de los dos informes lo midió — lo marco como deuda de medición para la fase 2, no como hallazgo.
4. **`MenuBarExtra` + app en Dock**: sin `LSUIElement` (grep vacío en Scripts/Resources). Decisión de superficie no documentada en ningún informe: ¿la app vive en menu bar (como SuperWhisper) o en Dock (como Granola)? Hoy hace ambas. Menor, pero es de las que conviene decidir conscientes.

## Qué rechazo de plano

- **C (whisper.cpp/WhisperKit) para live**: coincidimos (su P0-1, mi "no copiar"), pero lo dejo asentado con un argumento que GLM no usó: C pierde `volatileResults` — y el volátil en itálica es literalmente la mitad de la experiencia "live" que el humano pidió (`MeetingDetailView.swift:272-281`, `RecordingHUD.swift:147-161`). Cambiar de motor para "parecerse más a SuperWhisper" eliminando la feature que más se parece a SuperWhisper sería circular.
- **B como reemplazo del live multilingüe**: la vía liviana de streaming en 0.15.2 es **en-only** (EOU 120M); la multilingüe es 0.6B (su propia tabla). Para una app cuyo default de probes es en+es, B-live es una regresión de producto aunque mida mejor en RAM. B cabe solo en D (batch al parar) o como opt-in "English only, low power".

## Convergencias (para que Grok no las discuta)

- API default off, clipboard gated, webhook loop gated, detector fuera de main, throttle de niveles, debounce de search, precalentar speech assets: **7 fixes, todos ≤10 líneas, ambos informes de acuerdo**. Es el quick-win pack de la fase 3.
- Productividad injertada: los dos llegamos a lo mismo desde lados opuestos — GLM: "no es recursos, es foco" (su §Recortes 7); yo: "no borrar, off por defecto" (mi P1). Misma conclusión: **gating, no amputación**.
- Motor live: no tocar. OSS local cabe en post-proceso (D) si el humano lo quiere, y es puerta de dos sentidos.

## Adjudicación, ronda 2 (Kimi, verificada)

GLM rebatió dos puntos de esta réplica; verifiqué ambos en el código antes de responder:

1. **Webhooks huérfanos — concedo, retiro el punto.** `webhookDelivery.webhookID` tiene `onDelete: .cascade` (`AppDatabase.swift:79-80`) y GRDB 7.11.0 trae `foreignKeysEnabled = true` por defecto (`GRDB/Core/Configuration.swift:28`, aplicado en `Database.swift:575`); la app usa `DatabaseQueue(path:)` con config por defecto (`AppDatabase.swift:21`). Borrar el webhook purga sus entregas pendientes. El `guard !webhooks.isEmpty` ingenuo es seguro.
2. **Tap que nunca fluyó — concedo, invertí los bloques.** `RecordingEngine.swift:117-127` sí cubre `systemBufferCount == 0`: 8 restarts + warning persistente. Mi "falta health-check del caso TCC" era incorrecto. Residual honesto (P2, compartido con GLM): el copy del warning hedged ("it only flows while sound is playing") no distingue "nadie habla" de "TCC denegado" en una reunión con audio — visibilidad, no detección.

GLM concede P1-2(b) y (c) (default de probes y decisión de idioma), con timeout en segundos de habla, no wall-clock — lo apunto como refinamiento correcto: wall-clock penaliza al usuario que tarda en hablar; segundos de habla mide evidencia real. Ronda cerrada.
