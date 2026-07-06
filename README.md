# ClaudeMeter

App de barra de menú para macOS que muestra el **consumo de Claude Code**:
costo estimado de hoy y % de la sesión en el ícono, y en la ventana los
**límites del plan** (sesión de 5 h, semana, semana Opus — lo mismo que
`/usage`), el desglose de tokens (input / output / cache), costo por modelo
y los últimos 7 días.

Misma arquitectura que InstaDM: **agent app** (`LSUIElement`, sin Dock),
SwiftPM puro sin Xcode project, firma **ad-hoc**, distribución fuera del
App Store.

## Cómo funciona

Lee los transcripts locales de Claude Code (`~/.claude/projects/**/*.jsonl`),
que registran los tokens de cada mensaje del asistente, y calcula el costo
con la tabla de precios oficial de Anthropic (julio 2026):

| Modelo | Input $/M | Output $/M |
|--------|-----------|------------|
| Fable 5 / Mythos 5 | 10.00 | 50.00 |
| Opus 4.5–4.8 | 5.00 | 25.00 |
| Opus ≤4.1 | 15.00 | 75.00 |
| Sonnet (todas) | 3.00 | 15.00 |
| Haiku 4.5 | 1.00 | 5.00 |

Cache write = 1.25× input, cache read = 0.1× input.

Detalles de implementación:

- **Escaneo cada 60 s** con cache por archivo (mtime + tamaño) — solo se
  re-parsean los transcripts que cambiaron.
- **Deduplicación global** por `message.id + requestId`: el mismo mensaje
  puede aparecer en varios archivos tras un resume o fork de sesión.
- Archivos con más de 8 días no se tocan.
- El costo es una **estimación** (no refleja descuentos, batch al 50%, ni
  precios intro).

## Límites del plan (como /usage)

Los porcentajes de la sesión de 5 horas y de la semana salen del endpoint
OAuth de Claude Code (`GET api.anthropic.com/api/oauth/usage`) — el mismo
que alimenta `/usage`. Detalles:

- El token se lee del **Keychain** ("Claude Code-credentials") con fallback
  a `~/.claude/.credentials.json`. La primera vez macOS pide permiso para
  acceder al ítem del Keychain — "Permitir siempre".
- El endpoint **no está documentado y rate-limita agresivo**: se consulta
  cada 5 minutos, con backoff de 15 ante un 429 (se conserva el último dato).
- Si el token expiró, la app lo avisa — abrir Claude Code lo renueva solo.
- Esta es la única llamada de red de la app; el resto es lectura local.

## Compilar y correr

```sh
make test     # corre los tests
make bundle   # compila release y arma dist/ClaudeMeter.app (firma ad-hoc)
make run      # bundle + abre la app
```

Requisitos: macOS 14+, Swift 6 (Command Line Tools alcanza).

## Estructura

```
Sources/ClaudeMeter/
├── ClaudeMeterApp.swift    # @main, MenuBarExtra con el costo de hoy
├── UsageStore.swift        # agregados (hoy, por modelo, 7 días) + polling
├── Support/
│   ├── Pricing.swift       # tabla de precios y cálculo de costo
│   └── UsageScanner.swift  # parseo de los JSONL con cache y dedupe
└── Views/UsageView.swift   # panel: total, grid de tokens, modelos, días
Tests/ClaudeMeterTests/     # pricing + parser
```
