# @voxd/cli

Operator CLI for [Vox](https://github.com/arach/vox) — the local-first voice stack. Install and manage the companion daemon, warm models, transcribe audio, synthesize speech, inspect performance, and recover stuck sessions.

Installs the `vox` binary.

| Surface | Package |
|---------|---------|
| Operator CLI | **`@voxd/cli`** (this package) |
| Bun / Node companion client | [`@voxd/sdk`](https://www.npmjs.com/package/@voxd/sdk) |
| Browser / extension HTTP client | [`@voxd/client`](https://www.npmjs.com/package/@voxd/client) |
| Native Apple apps | Embed Swift packages (`VoxCore`, `VoxEngine`) directly |

## Install

```bash
npm install -g @voxd/cli
```

Requires **Node 22+** on macOS with Vox Companion available.

### First-time setup

1. Install the menu bar app / companion from [voxd.cc/download](https://voxd.cc/download) (provides the `voxd` binary), **or** build from a repo checkout.
2. Register the LaunchAgent and verify health:

```bash
vox install
vox doctor       # expect ready: true
```

`vox install` wires a LaunchAgent to an existing `voxd` at `~/.vox/bin/voxd` (or a dev build). It does not download models by itself.

From a monorepo checkout instead of a global install:

```bash
bun install && bun run build
node packages/cli/dist/index.js doctor
```

## Quick start

```bash
# Health
vox doctor
vox daemon status

# Speech to text
vox warmup start parakeet:v3
vox transcribe file --model parakeet:v3 --metrics --timestamps /path/to/audio.wav
vox transcribe bench --model parakeet:v3 /path/to/audio.wav 5

# Text to speech
vox voices --model avspeech:system
vox speak --model avspeech:system --metrics "Hello from Vox"
vox speak bench --model avspeech:system "Hello from Vox" 5

# Observability
vox perf dashboard --client vox-cli
vox logs daemon --tail 80
vox history list --limit 20
```

## Commands

```text
vox install
vox uninstall
vox daemon start|stop|status
vox doctor
vox models list|install|preload [modelId]
vox warmup status|start [modelId]
vox warmup schedule [delayMs] [modelId]
vox perf dashboard [--client <clientId>] [--route <route>] [--last <n>]
vox history [list] [--client <clientId>] [--model <id>] [--source file|live] [--limit <n>] [--json]
vox history delete <id>
vox logs [daemon|performance|voice|history] [--tail <n>]
vox transcribe file [--model <id>] [--metrics] [--timestamps] <path>
vox transcribe bench [--model <id>] <path> [runs]
vox transcribe status
vox transcribe cancel [sessionId]
vox transcribe live [--model <id>] [--timestamps]
vox speak [--model <id>] [--voice <id>] [--output <path>] [--speed <n>] [--instructions <text>] [--metrics] [--no-play] <text>
vox speak bench [--model <id>] [--voice <id>] [--speed <n>] [--instructions <text>] <text> [runs]
vox voices [list] [--model <id>]
vox tui
```

### Daemon lifecycle

| Command | Purpose |
|---------|---------|
| `vox install` | Register LaunchAgent for `voxd` |
| `vox uninstall` | Remove LaunchAgent |
| `vox daemon start` | Ensure companion is running |
| `vox daemon stop` | Stop companion |
| `vox daemon status` | Show process / port status |
| `vox doctor` | Run readiness checks |

### Models and warm-up

```bash
vox models list
vox models install parakeet:v3
vox models preload parakeet:v3
vox warmup status
vox warmup start parakeet:v3
vox warmup schedule 500 parakeet:v3
```

Warm-up is a public runtime control: skip cold-start cost before user-facing transcription or synthesis.

### Transcription

```bash
vox transcribe file --model parakeet:v3 --metrics --timestamps /tmp/sample.wav
vox transcribe bench --model parakeet:v3 /tmp/sample.wav 5
vox transcribe live --model parakeet:v3 --timestamps
vox transcribe status
vox transcribe cancel
```

- **`file`** — offline clip (best for benchmarks; no mic capture in the measurement)
- **`bench`** — warm-path variance over N runs
- **`live`** — microphone session with partials
- **`status` / `cancel`** — recover a stuck live session

### Synthesis

```bash
vox voices --model avspeech:system
vox speak --model avspeech:system --voice <id> --metrics "Hello from Vox"
vox speak --output ./hello.wav --no-play "Save without playing"
vox speak bench --model avspeech:system "Hello from Vox" 5
```

### Logs, history, and performance

```bash
vox logs daemon --tail 120
vox logs performance --tail 40
vox history list --client vox-cli --limit 20
vox history list --json
vox history delete <id>
vox perf dashboard
vox perf dashboard --client vox-cli --route synthesize.generate --last 50
```

Performance samples live at `~/.vox/performance.jsonl` with `clientId`, `route`, and `modelId`.

## Reading metrics

| Field | Meaning |
|-------|---------|
| `inferenceMs` | Hot ASR model work |
| `synthesisMs` | Hot TTS generation |
| `totalMs` | End-to-end wall time |
| `modelLoadMs` | Cold load (spikes mean warm-up, not inference regression) |
| `realtimeFactor` | Audio duration / model work |

Use `bench` after `warmup start` or `models preload` when comparing warm-path latency.

## Common failures

| Symptom | Fix |
|---------|-----|
| Companion not ready | `vox install` then `vox daemon start` / `vox doctor` |
| Missing ASR model | `vox models list` → `vox models install <id>` |
| Cold latency spikes | `vox warmup start <modelId>` |
| TTS voice mismatch | `vox voices --model <id>` then pass `--voice` |
| Stuck mic / live session | `vox transcribe status` then `vox transcribe cancel` |
| No perf data | Run a `transcribe` or `speak` first |
| External provider issues | Check `~/.vox/providers.json` and provider env |

## External providers

Non-default ASR/TTS engines register in `~/.vox/providers.json` and are selected with `--model`. See the [Provider Protocol](https://github.com/arach/vox/blob/main/docs/providers.md).

## Environment

| Variable | Default | Role |
|----------|---------|------|
| `VOX_PORT` | `42137` | Companion WebSocket port |
| `VOX_BRIDGE_PORT` | `43115` | HTTP bridge (browser clients) |
| `VOX_HOST` | `127.0.0.1` | Bind host |
| `VOX_HOME` | `~/.vox` | Runtime data directory |

## Programmatic use

The CLI is a thin operator surface over `@voxd/sdk`. For app integrations, use the SDK directly:

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "my-tool" });
await client.connect();
// ...
```

## Docs

- [Quickstart](https://github.com/arach/vox/blob/main/docs/quickstart.md)
- [Runtime](https://github.com/arach/vox/blob/main/docs/runtime.md)
- [Observability](https://github.com/arach/vox/blob/main/docs/observability.md)
- [Provider protocol](https://github.com/arach/vox/blob/main/docs/providers.md)

## License

MIT
