# Runtime

## Core Flow

1. A client connects to `voxd` over local WebSocket JSON-RPC.
2. The runtime resolves health, model state, and optional warm-up state.
3. The client triggers file transcription or a live session.
4. `VoxEngine` runs Parakeet locally and returns transcript text, word timings, and stage metrics.
5. The runtime records a tagged performance sample to `~/.vox/performance.jsonl`.

## Warm-Up Semantics

Warm-up is public runtime behavior, not a hidden side effect.

Available RPC surfaces:

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

This allows apps to:

- warm immediately when a user opens a dictation affordance
- schedule warm-up shortly before expected use
- observe whether a model is already hot

Typical usage pattern:

1. The app creates a `VoxClient` with a stable `clientId`
2. The app schedules or starts warm-up when the user opens a voice affordance
3. The app issues `transcribe.file` or a live session request after the runtime is hot

## File Transcription

`transcribe.file` is the cleanest path for benchmarks and end-to-end verification because it removes microphone capture from the measurement path.

The runtime returns:

- transcript text
- word-level timestamps with confidence
- `modelId`
- elapsed runtime
- stage-level metrics when requested or available

## Route Semantics

Current route names worth preserving:

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.stopSession`
- `transcribe.cancelSession`
- `warmup.status`
- `warmup.start`
- `warmup.schedule`

These route names matter because they are also telemetry dimensions.

## Live Sessions

Live sessions are coordinated in `VoxService`.

Key properties:

- one active session at a time today
- session ownership is associated with both `connectionID` and `clientId`
- stop/cancel semantics are explicit
- final transcript events include metrics and word-level timestamps

## Important Swift entry points

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ParakeetProvider.swift`
