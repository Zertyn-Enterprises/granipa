# Orquestación Grañipa — 2026-09-03

Grok orquesta. Kimi (`granipa-kimi`, k3[1m]) y GLM (`granipa-glm`, glm-5.3[1m] xhigh) auditan en paralelo. El humano pidió: auditoría completa, UI/UX, transcripción local OSS tipo SuperWhisper, menos recursos, simplificar.

## Sesiones (verificado 2026-09-03)

| Rol | tmux | pid | session uuid | modelo |
|---|---|---|---|---|
| Grok (orquesta) | `granipa:granipa-grok` | 35691 | `01a0663e-3e22-78a1-925d-b1f84d181074` | grok-4.6 |
| Kimi | `granipa:granipa-kimi` | 68348 | `e36502c8-64a8-48cc-a4d5-5dae5f813fd3` | k3[1m] |
| GLM | `granipa:granipa-glm` | 68705 | `3236d4cb-3d71-4527-9869-ab5cda13ccf5` | glm-5.3[1m] xhigh |

Checkout compartido: `~/Dev/02_hq/granipa` @ `main` (limpio, = origin/main). App idle: pid 28248, ~99 MB RSS.

## Canal

Grok no tiene `SendMessage`. Claude sí. Por eso el canal fiable Grok↔Kimi↔GLM es **ficheros** en `docs/wip/2026-09-03-*.md`.

- Kimi ↔ GLM: `SendMessage` permitido (mismo repo). Un mensaje por evento, no chat.
- Eventos: `landed:` (entregaste un fichero), `blocked:`, `decision:`.
- No commits. No ramas. No código. Fase 1 = solo lectura + informes.
- No tocar `main`. No crear `CONTEXT.md` / `AGENTS.md` / `PLAN.md`.

## Fases

1. **Auditoría adversarial (ahora).** Kimi y GLM independientes. Luego réplica del informe del otro.
2. **Síntesis (Grok).** Plan + opciones. El humano decide las puertas de un sentido (motor ASR, recorte de superficie).
3. **Implementación.** Worktrees separados. Grok reparte. Cross-review entre familias.

## Hechos ya verificados por Grok (no redescubrir como si no existieran; sí contradecir si el código dice otra cosa)

- Live ASR actual: Apple `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26), dos canales (mic=Me, system=Them). Ya es streaming on-device.
- SuperWhisper realtime **solo** en Nova (cloud). Local SW = whisper.cpp (75 MB–3 GB) + Parakeet/WhisperKit. No es live local.
- `Package.swift` ya pinea FluidAudio **exact 0.15.2** y lo linkea. `CLAUDE.md` miente: dice que está comentado.
- FluidAudio (docs actuales, no necesariamente 0.15.2): Parakeet TDT batch, Parakeet EOU 120M streaming, pyannote diarization. ANE, no GPU.
- Siempre encendido hoy: clipboard poll 700 ms, detector reuniones 5 s, API localhost :7799 default on, webhook loop 30 s, calendar, Sparkle.
- Language auto: hasta 3 locales × 2 canales = hasta 6 `SpeechAnalyzer` en paralelo al arrancar un recording.
- Superficie: meetings + clipboard + OCR + window manager + API + webhooks. Settings: 8 tabs, 607 líneas.

## Producto (tensión, no decidirla vosotros)

Grañipa es meeting notes (Granola-like), no dictado overlay (SuperWhisper-like). El humano pidió “transcripción en tiempo real con modelo local OSS como SuperWhisper” **y** “mínimos recursos”. Esas dos piden direcciones distintas. Informe: tradeoffs, no implementación.

## Entregables

| Quién | Fichero |
|---|---|
| Kimi | `docs/wip/2026-09-03-kimi-hallazgos.md` luego `docs/wip/2026-09-03-kimi-replica.md` |
| GLM | `docs/wip/2026-09-03-glm-hallazgos.md` luego `docs/wip/2026-09-03-glm-replica.md` |
| Grok | `docs/wip/2026-09-03-sintesis.md` (después) |

Formato de hallazgos: hechos verificados vs inferencias etiquetadas. Cada hallazgo: archivo:línea, severidad (P0/P1/P2), coste de arreglo, riesgo de no tocarlo. Nada de “probablemente”.
