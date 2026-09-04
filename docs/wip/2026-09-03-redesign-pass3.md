# Pass 3 — el humano no notó el pass 2

Screenshot del overlay: waveform = una línea de puntitos, copy duplicado, caja genérica. Cita: *subir el listón muchísimo. prácticamente no se nota nada*.

Grok rehace el overlay AHORA: 40 barras altas, idle breathing, anillo accent, 22pt Speak, failed sin duplicar, PanelMotion rise 40pt / 340ms.

## Kimi — tiene que verse en un screenshot

1. **HUD de reunión** del mismo tamaño visual que el overlay nuevo (ancho ~520, waveform o snippet a 22pt, material, anillo). Si sigue siendo una pastilla chica, fallaste.
2. **Home**: título más presente, Record large (Grok ya subió el botón), filas ~52pt, hero card más cinematográfica. Un before/after de screenshot debe ser obvio.
3. **Clipboard panel**: no un rectángulo plano. Misma abertura (PanelMotion ya). Interior tipo Raycast: type 15+, más aire, hover claro.

No nits de 1px. `swift build`. Append log. No pises DictationOverlayView / DictationController / PanelMotion.

## GLM

Mic RMS: confirma que `AudioChunk`/buffer.rmsLevel no está aplastado a ~0 (por eso se veían puntitos). Si el nivel real es bajo, sube el mapping en un helper puro `WaveformGain.display(rms:)` y tests. Grok ya hace `pow(level*14, 0.45)` en pushLevel; si hay un sitio mejor, muévelo ahí y cubre con test. No UI.
