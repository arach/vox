# Runtime

## Core Flow

1. A client connects to `voxd` over local WebSocket JSON-RPC.
2. The runtime resolves health, model state, and optional warm-up state.
3. The client triggers file transcription, a live ASR session, one-shot synthesis, or a synthesis session.
4. `VoxEngine` resolves the right ASR or TTS provider and returns transcript text, word timings, or WAV bytes plus stage metrics.
5. The runtime records a tagged performance sample to `~/.vox/performance.jsonl`.
6. The daemon appends operational logs to `~/.vox/logs/voxd.log`.

## Warm-Up

Warm-up is a public API, not a hidden side effect. It applies to both ASR and TTS models.

- `warmup.status` -- check if the model is hot
- `warmup.start` -- warm immediately
- `warmup.schedule` -- warm after a delay

Typical pattern: create a `VoxClient` with a stable `clientId`, warm when the user opens a voice affordance, then transcribe or synthesize once the model is ready.

## File Transcription

`transcribe.file` is best for benchmarks because it takes mic capture out of the measurement. Returns transcript text, word-level timestamps, `modelId`, elapsed time, and stage metrics.

## Synthesis

`synthesize.voices` lists available voices for a TTS model.

`synthesize.generate` returns:

- `modelId`
- `voiceId`
- `format`
- `contentType`
- base64-encoded audio bytes
- elapsed time
- synthesis metrics

Longer-running output flows use:

- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`

## RPC Routes

The runtime exposes these RPC routes:

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`
- `synthesize.voices`
- `synthesize.generate`
- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`
- `warmup.status`
- `warmup.start`
- `warmup.schedule`

## Performance routes

These are the route values currently emitted into `performance.jsonl`:

- `transcribe.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

Cancelled synthesis sessions are currently recorded as `synthesize.startSession` with `outcome: "cancelled"`.

## Live Sessions

Speech sessions are coordinated in `VoxService`. Session ownership ties to both `connectionID` and `clientId`. Stop and cancel are distinct operations. Final transcript events include metrics and word-level timestamps. Synthesis session status includes the selected model and voice. Active session state is inspectable for operator recovery.

## Configuration

Ports and bind address are configurable via environment variables.

Vox uses two named companion ports:

| Role | Default | Transport | Env var | Stored |
|------|---------|-----------|---------|--------|
| `companion-ws` | `42137` | WebSocket | `VOX_PORT` | `runtime.json` |
| `companion-http` | `43115` | HTTP | `VOX_BRIDGE_PORT` | process/env only |

`companion-ws` is the `voxd` daemon port that `@voxd/sdk` discovers through `~/.vox/runtime.json`. `companion-http` is the browser-facing bridge port used by `@voxd/client`.

The bind host is shared across both surfaces:

| Variable | Default | Description |
|----------|---------|-------------|
| `VOX_PORT` | `42137` | `companion-ws` daemon WebSocket port |
| `VOX_BRIDGE_PORT` | `43115` | `companion-http` bridge port |
| `VOX_HOST` | `127.0.0.1` | Bind address for both services |
| `VOX_HOME` | `~/.vox` | Runtime data directory |

CLI flag `--port` takes precedence over env vars for both `voxd` and `voxbridge`.

## Important Swift entry points

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/SynthesisSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ProviderRegistry.swift`
- `swift/Sources/VoxEngine/TTSProviderRegistry.swift`
