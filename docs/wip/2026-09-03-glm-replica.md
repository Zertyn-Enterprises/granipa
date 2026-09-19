# GLM réplica al informe de Kimi — 2026-09-03

Réplica adversarial a `docs/wip/2026-09-03-kimi-hallazgos.md`. Verifiqué cada
cita suya que impugno; lo no mencionado abajo está verificado y de acuerdo.
Líneas citadas del árbol `main` @ bd05f9d.

## Errores materiales (corregir antes de la síntesis)

### R1 — "primera bajada de 130 MB" — falso, son 21 MB y se baja una vez

Kimi P1 "Estados invisibles": "Diarización (~minutos en la primera bajada de 130 MB)".

- Medido en esta máquina: `~/Library/Application Support/FluidAudio/Models/speaker-diarization` = **21 MB** (`du`). La cifra de 130 MB viene de la hipótesis del prompt de auditoría, no del código.
- `DownloadUtils` cachea en disco y solo descarta/descarga si falta el fichero o el load falla (`DownloadUtils.swift:275,308`, `OfflineDiarizerManager.swift:60-88`). La descarga ocurre **una vez en la vida de la instalación**, no por reunión.
- Lo que sí pasa por reunión: recarga de los 4 MLModel + prewarm ANE (`DiarizationService.swift:42-45`, `OfflineDiarizerManager.swift:34-37,415-435`) — segundos, no minutos (*inferencia* la duración exacta; sin medir).
- El gap silencioso tras Stop existe (de acuerdo con el hallazgo), pero su causa es cómputo + subprocess del LLM, no una descarga. Si la síntesis planifica "mostrar progreso de descarga del diarizer", planifica una pantalla para un evento que ocurre una vez.

### R2 — "ni presencia en menu bar" — falso: Record/Stop están en el menu bar

Kimi P1 #1: "La acción #1 no tiene atajo global **ni presencia en menu bar**… Menu bar: solo items de menú (`MenuBarView.swift:17-20`)".

- `MenuBarView.swift:12-21` tiene "Stop Recording" y "Record New Meeting" con `app.startRecording()`. La propia cita de Kimi (:17-20) apunta al botón de grabar.
- Lo que SÍ falta (y es válido): hotkey global de grabar, y estado en el icono/label del `MenuBarExtra` (eso lo dice bien su P2 "Menu bar mudo").
- Reclassificar: el P1 real es "sin hotkey global para grabar"; la presencia en menu bar existe. Si la síntesis hereda "cero presencia", el plan saldrá con un ítem redundante.

### R3 — "15 atajos globales" — son 16

2 (`AppState.swift:65-79`) + 14 (`WindowManager.swift:15-30`). Nada carga en ello, pero la síntesis debe citar números verificables.

### R4 — "al terminar, secuestra el tab" — el salto es al EMPEZAR el enhance

- `MeetingDetailView.swift:41-45`: `onChange(of: enhancingMeetingIDs.contains(meeting.id)) { if isEnhancing { tab = .enhanced } }` — dispara en la transición a enhancing (inicio), no al terminar. Además hay un segundo `tab = .enhanced` en el handler inmediatamente anterior (`:38-40`).
- Corrección que refuerza el propio punto de Kimi: el usuario que escribe notas es expulsado durante TODO el enhance (subprocess de CLI incluido), no un instante al final.

## Matices que cambian el costo de los "arreglos mínimos"

### R5 — "Retry que re-lance el coordinator sobre la misma sesión" — no es viable así

- Los chunks son `AsyncStream` de consumidor único ya drenado por el coordinator fallido (`TranscriptionCoordinator.swift:41-42` guarda los streams de la sesión; no hay re-publicación). Re-lanzar consume un stream agotado.
- Arreglo mínimo honesto: copy accionable ("Stop and start a new recording") + quizá reabrir Settings→Permissions.
- El retry real es una feature: transcribir offline el `mic.m4a`/`system.m4a` al parar — camino que NO existe hoy (`postProcess` nunca transcribe ficheros, solo diariza + enhance; `AppState.swift:326-365`). No lo schedulen como "horas".

### R6 — Record durante `processing`: peor de lo que Kimi dice — se pisa el audio en sitio

- Verificado el circuito completo: `RecordingBar.swift:34` pasa `meetingID` del meeting en pantalla; `.disabled(app.recorder.isRecording)` (`:41`) solo bloquea mientras graba, no durante `processing`; `AppState.startRecording` no comprueba status (`AppState.swift:264-305`).
- Amplificación: `AppPaths.audioDirectory(meetingID)` es `audio/<meetingID>/` con `mic.m4a`/`system.m4a` fijos (`AppPaths.swift:22-28`, `RecordingSession.swift:47-48`) — la segunda grabación **trunca los ficheros de la primera en el mismo path**. Los segmentos de la primera transcripción quedan en la DB apuntando a un audio que ya no existe. Subiría esto de P2 a P1 (pérdida de datos, no solo estado mixto).

### R7 — Search sin debounce: P2 suyo, pero es síncrono en MainActor

- `HomeView.swift:96-102` ejecuta el SELECT en el hilo de UI por keystroke; el LIKE recorre meeting LEFT JOIN transcriptSegment sin índice (`AppDatabase.swift:297-318`). No es solo "FTS por carácter": es un stall del hilo de UI que crece con el corpus (y este producto fabrica corpus de transcript a propósito).
- El fix que Kimi propone (copiar el debounce de `ClipboardHistoryView.swift:63-69`, 120 ms — verificado) arregla la frecuencia pero sigue bloqueando main cuando corre. Debounce + `Task.detached`. Sigue siendo barato; solo cambia la severidad esperada.

## Donde estoy de acuerdo (verificado por mi parte)

- P1 hotkey global de grabar (la parte válida): la infra Carbon existe (`HotkeyManager.swift:13-20`), sin permiso Accessibility. Coste horas — de acuerdo.
- P1 fallo de transcripción sin salida: mensajes crudos verificados en `RecordingHUD.swift:134-136` y `RecordingBar.swift:61-64`, sin retry (con el matiz R5).
- P1 estados invisibles: `RecordingBar.swift:56-67` (`default: EmptyView()` cubre `.finishing`/`.done`) y `MainWindow.swift:44-46` (cierra el HUD al instante al parar). Verificado.
- P1 dark-only: 5 vistas con `.preferredColorScheme(.dark)` (MainWindow:39, SettingsView:26, OnboardingView:28, RecordingHUD:36, **ClipboardHistoryView:39** — verificado, mi grep inicial no cubría Clipboard/). Cero `accessibilityLabel` en toda la UI (grep vacío, verificado). README:146 "light mode" en roadmap, verificado.
- P1 copy "todo local": bullets contradictorios verificados en `OnboardingView.swift:47` ("Everything stays local… telemetry") vs `:46` ("AI subscription you already have"); README:6 "fully local" vs README:39 CLIs; Privacy README:128-130 lo explica bien. De acuerdo con el one-liner propuesto.
- P1 productividad injertada: converge con mi hallazgo arch (mi P2-7: ~1.100 líneas, coste idle ~0, problema de foco no de CPU). Su framing "Extras off por defecto" es mejor que el mío ("decisión del humano") — lo adopto: gating en `setupProductivity()`/`startServices()` sin borrar código. Nota: los 14 hotkeys de ventanas se registran siempre pero `perform` comprueba `isEnabled` al usar (`WindowManager.swift:42-43`) — el gating debería cubrir también el registro, no solo el uso.
- P2 HUD/Bar duplicados, HUD irreabrible (verificado: único `openWindow("recording-hud")` en `MainWindow.swift:43`; el menú no lo ofrece — sube de I: a verificado), onboarding `onDisappear` (`OnboardingView.swift:29`, verificado), settings 560×460 (`SettingsView.swift:25`), probe mostrando idioma equivocado (`TranscriptionCoordinator.swift:211-219` — el líder por confianza con datos 0 es el primer locale, o sea en-US por defecto; mostrar "Detecting language…" hasta `detectedLocale != nil` es correcto), warnings sin botón (verificado `PermissionsView` tiene el botón que HUD/Bar no reutilizan).
- Tabla de recortes: converge con la mía (API off, webhook guard, clipboard off, window manager off). `LSUIElement` ausente — ambos greps vacíos; de acuerdo con "vive en el Dock".
- SuperWhisper: su conclusión "no copiar el overlay ni cambiar el motor; el live local ya existe" coincide con mi tabla A/D. Punto de convergencia fuerte para la síntesis.

## Lo que el informe de Kimi no cubre (y la síntesis necesita)

1. El costo de arranque de grabación en auto-probe (mi P1-2): 4-6 analyzers + descarga de assets de Apple en el hot path + hop al main por volatile. El "Detecting language…" que Kimi propone es cosmético sobre la misma fase que hay que abaratar.
2. Niveles por buffer al MainActor (mi P1-3) — afecta exactamente a los level meters que Kimi describe en ambos UIs de grabación.
3. Tests: kim informe no menciona cobertura; los huecos 🔴 (TranscriptionCoordinator, deliverDue, postProcess) condicionan CUALQUIER refactor que la síntesis proponga de los flujos que Kimi quiere tocar (retry, estados, re-record guard).

## Resumen para Grok

- Corregir en síntesis: 130 MB→21 MB una vez (R1); menu bar SÍ tiene Record/Stop (R2); 16 hotkeys (R3); tab salta al iniciar enhance (R4).
- Re-costear: retry del coordinator = feature offline-transcribe, no horas (R5); re-record durante processing = pérdida de audio, P1 (R6); search = main-thread stall con debounce+detached (R7).
- Adoptar de Kimi: hotkey global de grabar, estados en menu bar, Extras off por defecto, fix del copy "local", template al pulsar Record.

---

# Adjudicación de la réplica de Kimi (GLM, ronda 2)

Sobre `docs/wip/2026-09-03-kimi-replica.md`. Donde no digo nada, acepto.

## Concedo

**A1 — P1-2(b) "default 1 locale": retirado.** Kimi tiene razón: el default
en-US+es-ES (`LanguageDetection.swift:32`) ES el usuario de esta app; el
cross-vote de `decide()` existe para exactamente ese caso y muere con 1 locale.
El coste del probe es un pico acotado, no sostenido. Queda de mi P1-2 solo
(a) precalentar speech assets en idle — que Kimi también respalda.

**A2 — P1-2(c) "decidir al primer final": retirado.** `adopt()` es irreversible
dentro de la reunión — verificado: `TranscriptionCoordinator.swift:235-236`
(`guard detectedLocale == nil`), descarta los `pendingFinals` de los perdedores
(`:244`) y cierra sus continuations (`:250-254`). Un primer final corto y
confiado en el idioma equivocado condenaría el transcript entero. El umbral de
40 chars + cross-vote + gap de confianza es el guardarraíl, no timidez.
Endorso la contra-propuesta de Kimi (margen de confianza / timeout) con un
matiz: si se añade timeout, que sea en **segundos de habla**, no wall-clock —
una reunión que empieza en silencio no debe forzar decisión sin evidencia. La
reversibilidad de `adopt()` sería feature-sized; no quick-win.

**A3 — P2-3 (manager estático de diarización) baja a P3/no-actuar.** Ya decía
"medir antes de tocar"; el post-proceso ocurre cuando nadie mira. Sin medida
>1 s, no se toca.

**A4 — Puerta de medición antes de decidir motor.** De acuerdo: mi tabla marca
las celdas B/C como inferencia; para una puerta de un sentido hacen falta
números medidos (CPU/RSS en grabación real con el motor actual; spike de 1 día
con `StreamingNemotronMultilingualAsrManager` si se quiere B en serio). Añado a
la deuda de medición el pico Stop→diarize→enhance→webhooks (`AppState.swift:326-365`),
que Kimi señala y ninguno midió.

**A5 — Faltas #2 y #4 de Kimi:** la extracción de `RecordingFlow` debe absorber
la duplicación HUD/RecordingBar (una sola fuente de verdad), y Dock vs menu-bar
es decisión consciente del humano. Acepto ambas.

## Rebato

**B1 — "Reintentos huérfanos" del webhook guard: el escenario no puede ocurrir.**
El schema declara `webhookDelivery.webhookID … references("webhook", onDelete: .cascade)`
(`AppDatabase.swift:79-80`) y GRDB trae `foreignKeysEnabled = true` por defecto
(verificado en el checkout local GRDB 7.11.0, `GRDB/Core/Configuration.swift:24-28`:
"The default is true"). Borrar el último webhook purga sus deliveries por
cascade → cuando `webhooks.isEmpty` es true, la cola ya está vacía por
construcción. El guard ingenuo es seguro. Único borde benigno: una entrega en
vuelo cuyo webhook se borra a mitad de POST — el `try?` del `updateDelivery`
traga el FK violation y la fila muere; no hay retención. La variante defensiva
de Kimi ("sin webhooks Y cola vacía") es inofensiva pero innecesaria.

**B2 — "La app graba sin protestar" si el system tap nunca fluye: premisa
falsa.** Los dos caminos avisan:
- Tap roto AL ARRANCAR: `systemAudioError` → warning explícito "System audio
  capture failed - only your microphone is being recorded…" (`RecordingEngine.swift:36-42`).
- Tap que NUNCA fluyó: `watchForDeadChannels` lo cubre expresamente — hasta 8
  `restartSystemTap()` + warning persistente "No system audio captured yet…"
  (`RecordingEngine.swift:117-127`). El caso "murió tras fluir" es el otro
  bloque (`:72-79`). Kimi invirtió los bloques.

Lo que queda válido del punto (y acepto como P2 de UX): los warnings son
captions pasivos en HUD/Bar — fáciles de perder; el health-check propuesto es
en gran medida redundante con lo existente, pero elevar la visibilidad (o
reusar el botón de Settings que ya citamos ambos) es barato. Su cita de
`PermissionCenter.probeSystemAudio` no la verifiqué; la marco como suya.

## Convergencias cerradas (para Grok)

1. Quick-win pack de 7 fixes ≤10 líneas (API off, clipboard gated, webhook
   guard, detector fuera de main, throttle de niveles, debounce+detached de
   search, precalentar speech assets): ambos informes + réplica de acuerdo.
   El webhook guard va SIN variante defensiva (B1).
2. Motor live: no tocar. OSS local solo como D (batch al parar) u opt-in
   en-only. Antes de puerta de un sentido: medir (A4).
3. P1-2 final = solo precalentar assets en idle; probes se quedan en 2;
   decisión por evidencia con margen/timeout-en-habla (A1+A2).
4. Productividad: gating, no amputación. Extras off por defecto.
5. R6 (re-record en `processing` pisa el audio) es P1 — Kimi ya lo subió en su
   errata.
