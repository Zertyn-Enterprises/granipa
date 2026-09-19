# Kimi hallazgos UI/UX — 2026-09-03

Auditoría de superficie, solo lectura. `V:` = verificado este session (archivo:línea). `I:` = inferencia etiquetada. Severidad P0 (rompe el job) / P1 (fricción seria) / P2 (pulido).

## Camino feliz (verificado)

1. Instalar → `MainWindow` abre `onboarding` si `onboardingCompleted == false` (`MainWindow.swift:53-57`).
2. Onboarding: 3 pasos (welcome → permisos explicados sin pedir nada → AI CLIs + atajos) (`OnboardingView.swift:12-17`). Buen copy, botón de copiar el `npm install`.
3. Reunión empieza → detector la ve (poll 5 s, `MeetingDetector.swift:40`) → banner in-app (`MainWindow.swift:60-85`) + notificación → botón Record.
4. Record → HUD flotante se abre solo (`MainWindow.swift:41-47`), transcript live en `MeetingDetailView` tab Transcript (volátiles en itálica + finales, `MeetingDetailView.swift:239-305`).
5. Stop → status `processing` → diarización → enhancement → tab Enhanced se auto-abre (`MeetingDetailView.swift:41-45`).

El camino existe y es coherente. **Se pierde en dos sitios: arrancar la grabación (fricción, sin hotkey global) y cualquier fallo de transcripción (callejón sin salida).**

## Hallazgos

### P1 — La acción #1 no tiene atajo global ni presencia en menu bar

- evidencia: `AppState.swift:65-79` registra solo ⌥⇧V (clipboard) y ⌥⇧T (OCR); `WindowManager.swift:15-40` registra 14 hotkeys de ventanas. Ninguno graba. Menu bar: solo items de menú (`MenuBarView.swift:17-20`).
- por qué duele: la app tiene **15 atajos globales para lo accesorio y cero para el job principal**. SuperWhisper entero es "pulsa tecla → habla" (verificado en sus docs: menu bar con toggle de grabación y estados, https://superwhisper.com/docs/get-started/interface-menu-bar). Aquí hay que abrir la app o el menú.
- arreglo mínimo: un `HotkeyManager.register` más (la infra ya existe, Carbon, sin permiso Accessibility — `HotkeyManager.swift:4`) + toggle "Record" en menu bar que ya existe. Coste: horas.
- riesgo de no tocarlo: el usuario percibe la app como "otra ventana que abrir", no como utilidad instantánea.

### P1 — Fallo de transcripción = callejón sin salida

- evidencia: `RecordingBar.swift:62` y `RecordingHUD.swift:135` pintan `Transcription failed: \(message)` en crudo (`error.localizedDescription`, `TranscriptionCoordinator.swift:141`). Sin botón de retry, sin sugerencia, sin link a Settings. La grabación sigue corriendo sin transcript.
- por qué duele: el fallo más probable (descarga de modelo falla, todos los probes fallan — `TranscriptionCoordinator.swift:132-142`) deja la reunión sin transcript y el usuario no sabe que parar y re-grabar es la única salida.
- arreglo mínimo: botón "Retry" que re-lance el coordinator sobre la misma sesión, o al menos copy accionable ("Stop and start a new recording — Settings → Permissions if it repeats"). Coste: bajo.
- riesgo: reuniones enteras sin transcript descubiertas al final.

### P1 — Estados `finishing`/`processing` invisibles o agresivos

- evidencia: `RecordingBar.swift:56-67` — `default: EmptyView()` cubre `.finishing` y `.done`; tras Stop el HUD se cierra al instante (`MainWindow.swift:44-46`) y la fila dice "Processing" (`HomeView.swift:203-206`) sin progreso. Diarización (~minutos en la primera bajada de 130 MB) + enhancement (subproceso CLI) pueden tardar decenas de segundos en silencio. Y al terminar, `MeetingDetailView.swift:41-45` **secuestra el tab del usuario** y lo manda a Enhanced aunque estuviera escribiendo notas.
- por qué duele: Stop → nada visible → el usuario no sabe si funcionó. Y el cambio de tab forzado interrumpe.
- arreglo mínimo: barra de estado en el header del detalle ("Identifying speakers… / Writing notes with Claude…") en vez del salto de tab; hacer el auto-switch solo si el usuario está en el tab Notes sin edits. Coste: bajo-medio.
- riesgo: sensación de app rota en el momento cumbre (fin de reunión).

### P1 — Dark-only + accesibilidad ausente

- evidencia: `.preferredColorScheme(.dark)` en 5 vistas (`MainWindow.swift:39`, `SettingsView.swift:26`, `OnboardingView.swift:28`, `RecordingHUD.swift:36`, `ClipboardHistoryView.swift:39`). `Theme.swift:14-21` todo hex fijo; `Color.white.opacity(...)` suelto en Sidebar/Home/HUD. Grep: cero `accessibilityLabel`, cero `dynamicTypeSize`, todos los textos a px fijos (11-15). `symbolEffect(.pulse)` y animaciones sin consultar Reduce Motion.
- por qué duele: el propio roadmap (README.md:146) promete light mode; cada hex suelto es deuda. Texto fijo a 12-13 px excluye a quien sube el tamaño del sistema.
- arreglo mínimo: no re-themear todo ahora; dejar de añadir hex fuera de `Theme` (regla), y migrar títulos serif a `.font(.title)` semánticos cuando se haga light mode. Coste: deuda controlada.
- riesgo: el light mode futuro cuesta el doble cada mes que pasa.

### P1 — Copy "todo local" contradicho en la misma pantalla

- evidencia: `OnboardingView.swift:47` bullet "Everything stays local: no accounts, no cloud, no telemetry" **dos bullets después** de "wand.and.stars — polished reports using the AI subscription you already have" (`:46`). README.md:6 "fully local" vs README.md:39 "shells out to claude/codex/gemini/grok CLI" (la sección Privacy :128-130 sí lo explica bien).
- por qué duele: es exactamente el punto donde un usuario privacy-conscious decide desinstalar o confiar. La contradicción es literal.
- arreglo mínimo: "Recording and transcription never leave your Mac. AI notes use the CLI subscription you choose — that's the only thing sent out." Una línea.
- riesgo: reviews/issues acusando false advertising en el punto fuerte del producto.

### P1 — La productividad injertada compite con el job

- evidencia: clipboard = vista de 390 líneas + panel NSPanel propio (`ClipboardHistoryView.swift`, `ClipboardPanelController.swift`) + poll 700 ms (`ClipboardMonitor.swift:19`); window manager = 14 hotkeys + permiso Accessibility (`WindowManager.swift`); OCR = permiso Screen Recording (`OCRService.swift`). Todo esto ocupa: 2 de 8 tabs de Settings, 1/3 del onboarding (step 2 entero, `OnboardingView.swift:126-136`), 2 items del menú, y 2 permisos "de miedo" en la lista de permisos (`PermissionsView.swift:54-63`).
- por qué duele: nada de esto sirve a "reunión → notas". El coste cognitivo lo paga el feature principal: el usuario nuevo aprende 3 atajos de cosas que no pidió antes de grabar su primera reunión. (El coste de CPU lo mide GLM.)
- arreglo mínimo: no borrar nada — convertir Productivity y Windows en módulos **off por defecto** con un solo tab "Extras" que los encienda. Hotkeys solo se registran si el módulo está on (hoy se registran siempre: `AppState.swift:58-80`). Coste: medio (gating de arranque, no reescritura).
- riesgo de no tocarlo: la app deriva a "navaja suiza" y el onboarding sigue vendiendo 3 productos a la vez.

### P2 — Dos UIs de grabación duplicadas y divergentes

- evidencia: `RecordingHUD.swift:84-172` (expanded) y `RecordingBar.swift:11-70` implementan lo mismo por separado: timer, level meters, warnings, estado de transcripción. Ya divergen: el HUD muestra el último segmento + volátiles (`RecordingHUD.swift:139-163`) y la barra no; la barra separa mic/system warnings, el HUD los fusiona (`RecordingHUD.swift:121`).
- arreglo mínimo: extraer un `RecordingStatusView` compartido. Coste: bajo.
- riesgo: cada fix de estados (P1 anterior) hay que hacerlo dos veces; ya se nota.

### P2 — Menu bar mudo durante lo importante

- evidencia: `GranipaApp.swift:22-28` — el icono cambia a `record.circle.fill` al grabar y nada más. Sin elapsed time, sin estado "processing", sin "Show HUD" en el menú (`MenuBarView.swift` entero).
- SuperWhisper (verificado docs): dot de colores por estado (loading/recording/processing/done) y click-to-toggle opcional.
- arreglo mínimo: `MenuBarExtra` con label de texto (mm:ss) al grabar, item "Show Recording HUD" que llame `openWindow(id: "recording-hud")`. Coste: horas.

### P2 — HUD irreabrible si se cierra

- evidencia: el único `openWindow(id: "recording-hud")` del código es el edge false→true de `isRecording` (`MainWindow.swift:41-47`). Es una `Window` scene (`GranipaApp.swift:38-46`), cerrable por el usuario. I: si la cierra a mitad de reunión, no hay camino de vuelta salvo parar y re-grabar (el menú no ofrece reabrirla).
- arreglo mínimo: el item de menú del hallazgo anterior lo resuelve. Coste: el mismo.

### P2 — Record re-utilizable durante `processing`

- evidencia: tras Stop, `recorder.isRecording` pasa a false y `RecordingBar` vuelve a mostrar Record habilitado (`RecordingBar.swift:41`) aunque el meeting esté en `.processing`. `AppState.startRecording(meetingID:)` (`AppState.swift:264-305`) no comprueba el status del meeting. I: re-grabar sobre el mismo meeting pisa los paths de audio al parar (`AppState.swift:316-317`) y relanza coordinator; el enhancement en vuelo (`enhancingMeetingIDs`) queda en estado mixto.
- arreglo mínimo: deshabilitar Record mientras `meeting.status == .processing`, o confirmación "This meeting already has a recording — replace it?". Coste: horas.

### P2 — Settings: 8 tabs, mezcla de audiencias

- evidencia: `SettingsView.swift:7-24`. Clasificación: **core** = General, Permissions, AI. **power-user** = Templates, API, Webhooks. **otro producto** = Productivity, Windows. La ventana fija 560×460 (`:25`) hace que Templates sea una lista de 120 px de alto (`:555`) y Webhooks un editor apiñado.
- arreglo mínimo: 5 tabs — General / AI (+Templates como sección o sub-tab) / Permissions / Extras (Productivity+Windows, off por defecto) / Advanced (API+Webhooks). Sin perder capacidad, solo reagrupar. Coste: medio.
- riesgo: cada feature nueva añade un noveno tab.

### P2 — Search sin debounce en Home (inconsistencia consigo misma)

- evidencia: `HomeView.swift:96-102` ejecuta `db.searchMeetings` por cada keystroke; `ClipboardHistoryView.swift:63-70` sí tiene debounce de 120 ms. FTS por carácter en una lista grande.
- arreglo mínimo: copiar el patrón del clipboard. Coste: minutos.

### P2 — Onboarding se marca completado al cerrar la ventana

- evidencia: `OnboardingView.swift:29` — `.onDisappear { onboardingCompleted = true }`. Cerrar la ventana en el paso 0 (botón rojo del traffic light) salta el tour para siempre.
- arreglo mínimo: marcar completed solo en "Get started". Coste: una línea.

### P2 — Sin pista de calendario cuando el permiso falta

- evidencia: el hero card solo existe si hay `nextEvent` (`HomeView.swift:68-70`); sin permiso de calendario el Home nunca menciona que la feature existe. El empty state (`:105-119`) tampoco.
- arreglo mínimo: una línea en empty state o banner suave "Connect your calendar to see upcoming meetings" cuando `calendar` está `notDetermined`. Coste: bajo.

### P2 — Probing de idioma muestra texto del idioma equivocado

- evidencia: durante el auto-probe, los volátiles que se muestran son los del probe líder por confianza (`TranscriptionCoordinator.swift:211-219`). I: en los primeros segundos el usuario puede ver texto basura del idioma perdedor en el HUD y en el transcript live.
- arreglo mínimo: mostrar "Detecting language…" hasta `detectedLocale != nil` en vez del volátil del líder. Coste: bajo.
- riesgo: bajo, pero es lo primero que ve un usuario bilingüe.

### P2 — Warnings de audio accionables pero sin botón

- evidencia: `RecordingEngine.swift:87-110` genera textos buenos ("Check System Settings > Privacy & Security > Microphone…"), pero `RecordingBar.swift:45-54` / `RecordingHUD.swift:121-125` los pintan como caption naranja sin el botón "Open Settings" que sí existe en `PermissionsView.swift:124-132`.
- arreglo mínimo: reutilizar ese botón junto al warning. Coste: bajo.

## SuperWhisper: qué copiar / qué no (y por qué)

Verificado en docs oficiales (introduction + interface-menu-bar, fetch hoy): SW es **dictado** — hotkey/menubar → hablas → texto pulido insertado; menu bar con dot de estado (yellow/red/blue/green); click-to-toggle opcional; modes = instrucciones AI por contexto; modelos cloud **o** locales a elegir.

**Copiar:**
1. Trigger instantáneo global (hotkey o click en menu bar). Es el 80% de la magia de SW y Grañipa no lo tiene — ver P1 #1.
2. Estados en menu bar (dot/elapsed/processing). Barato y visible siempre.
3. Modes ≈ lo que Grañipa ya llama Templates (`MeetingTemplate`). SW los pone al alcance del dedo en cada dictado; Grañipa los esconde en un menú del detalle (`MeetingDetailView.swift:139-160`). Copiar: elegir template **al pulsar Record** (o auto por calendario).

**No copiar:**
1. Overlay de dictado / insertar texto en el cursor. Es otro JTBD: Grañipa es notas de reunión (Granola-like), no dictado (SW-like). Añadirlo es el mismo error que el clipboard injertado.
2. Live transcription local tipo SW **ya existe**: SpeechAnalyzer hace streaming on-device word-by-word (README.md:35, `ChannelTranscriber`). Lo que falta no es el modelo sino acceso instantáneo y estados claros. Cambiar de motor ASR (Parakeet/whisper.cpp) es decisión de fase 2 con GLM; desde UX no hay demanda que lo justifique salvo calidad/latencia medida.

## Recorte de superficie (qué apagar por defecto)

| Feature | Hoy | Propuesta | Por qué |
|---|---|---|---|
| Window manager | on, 14 hotkeys (`WindowManager.swift:14`) | off por defecto, tab Extras | Conflicta con Rectangle (`SettingsView.swift:394-402`), exige Accessibility, no sirve al job |
| Clipboard history | on, poll 700 ms (`ClipboardMonitor.swift:19`) | off por defecto | 500 items en DB, panel entero, otro producto |
| OCR | on (hotkey) | on pero sin anunciar en onboarding | Un hotkey, permiso solo al usarlo; coste ~0 |
| API localhost :7799 | **on por defecto** (`AppState.swift:183-184`) | off por defecto | Servidor con bearer token escuchando para el 99% de usuarios que no lo usan; superficie de ataque y recursos por nada |
| Webhook loop 30 s | corre siempre (`AppState.swift:199-205`) | solo si hay webhooks activos | Trivial |
| Meeting detection | on (`AppState.swift:156-159`) | on | Es core del job |
| Sparkle | on | on | Es cómo llegan los fixes |

Nada de esto implica borrar código: gating de arranque en `setupProductivity()`/`startServices()`.

## Réplica pendiente / hecha

Hecha: `docs/wip/2026-09-03-kimi-replica.md` (réplica a GLM). La de GLM a este informe: `docs/wip/2026-09-03-glm-replica.md`.

## Errata (tras la réplica de GLM — verificada por mí)

- **R1 aceptada**: diarizer = 21 MB cacheados, descarga una vez (no "~130 MB por bajada"). Mi cifra venía del copy de la app (`SettingsView.swift:201`, README.md:103). Eso convierte el dato en hallazgo nuevo: **el copy de Settings/README sobreestima 6× la descarga** — P2 copy.
- **R2 aceptada**: el título de mi P1 #1 sobreafirmó. Menu bar SÍ tiene Record/Stop (`MenuBarView.swift:12-21`). El hallazgo real: **sin hotkey global para grabar** + icono sin estados. El cuerpo ya lo decía; el titular no.
- **R3 aceptada**: son 16 hotkeys globales (2 + 14), no 15.
- **R4 aceptada y agrava**: el tab salta al **iniciar** el enhance (`MeetingDetailView.swift:41-45` dispara en la transición a `true`), así que el usuario que escribe notas es expulsado durante todo el subprocess del CLI, no un instante.
- **R5 aceptada**: retry sobre la misma sesión no es viable (AsyncStream drenado, `TranscriptionCoordinator.swift:41-42`). Retry real = transcribir offline los m4a al parar — feature nueva, no "horas". El copy accionable sigue siendo el quick win.
- **R6 aceptada y sube a P1**: re-grabar durante `processing` **trunca los m4a en el mismo path** (`AppPaths.swift:22-28` nombres fijos) — pérdida de datos, no solo estado mixto. El guard pasa de P2 a P1.
- **R7 aceptada**: search = debounce **+ `Task.detached`**, no solo debounce.

## Correcciones a los "hechos verificados" de Grok

- ✅ Correcto: `Package.swift:10` pinea FluidAudio `exact: "0.15.2"` y lo linkea (`:18`); CLAUDE.md miente al decir "intentionally commented out". Además: como FluidAudio ahora **siempre** linkea, el `#if canImport(FluidAudio)` de `DiarizationService.swift:4` es rama muerta (I: queda de cuando era opcional).
- ✅ Correcto: clipboard 700 ms (`ClipboardMonitor.swift:19`), detector 5 s (`MeetingDetector.swift:40`), API :7799 default on (`AppState.swift:183-189`), webhook loop 30 s (`AppState.swift:203`).
- Matiz: "Settings: 8 tabs, 607 líneas" — 607 líneas el fichero; los 8 tabs verificados en `SettingsView.swift:7-24`.
- Añado: la app **no** es agent (sin `LSUIElement` en Scripts/Resources — grep vacío), así que vive en el Dock además del menu bar. Ni bueno ni malo, pero decide dónde "abrir" la app.
