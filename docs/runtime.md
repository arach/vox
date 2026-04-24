# Runtime

## Core Flow

1. A client connects to `voxd` over local WebSocket JSON-RPC.
2. The runtime resolves health, model state, and optional warm-up state.
3. The client triggers file transcription or a live session.
4. `VoxEngine` runs Parakeet locally and returns transcript text, word timings, and stage metrics.
5. The runtime records a tagged performance sample to `~/.vox/performance.jsonl`.
6. The daemon appends operational logs to `~/.vox/logs/voxd.log`.

## Warm-Up

Warm-up is a public API, not a hidden side effect.

- `warmup.status` -- check if the model is hot
- `warmup.start` -- warm immediately
- `warmup.schedule` -- warm after a delay

Typical pattern: create a `VoxClient` with a stable `clientId`, warm when the user opens a voice affordance, then transcribe once the model is ready.

## File Transcription

`transcribe.file` is best for benchmarks because it takes mic capture out of the measurement. Returns transcript text, word-level timestamps, `modelId`, elapsed time, and stage metrics.

## Routes

Route names double as telemetry dimensions. Current routes:

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`
- `warmup.status`
- `warmup.start`
- `warmup.schedule`

## Live Sessions

Coordinated in `VoxService`. One active session at a time. Session ownership ties to both `connectionID` and `clientId`. Stop and cancel are distinct operations. Final transcript events include metrics and word-level timestamps. Active session state is inspectable for operator recovery.

## Configuration

Ports and bind address are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VOX_PORT` | `42137` | Daemon WebSocket port |
| `VOX_BRIDGE_PORT` | `43115` | HTTP bridge port |
| `VOX_HOST` | `127.0.0.1` | Bind address for both services |
| `VOX_HOME` | `~/.vox` | Runtime data directory |

CLI flag `--port` takes precedence over env vars for both `voxd` and `voxbridge`.

## Important Swift entry points

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ParakeetProvider.swift`
