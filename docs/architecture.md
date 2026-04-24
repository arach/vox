# Architecture

## Layers

### VoxCore

Shared runtime types and utilities:

- runtime metadata
- transcription metrics
- performance samples
- filesystem paths
- trace utilities

### VoxEngine

Model-facing transcription layer:

- model installation and preload
- audio inspection and preparation
- Parakeet inference
- stage-level timing

### VoxService

Daemon-side orchestration:

- JSON-RPC bridge
- live session coordination
- microphone recording
- warm-up scheduling
- performance sample recording

### TypeScript SDK

`@voxd/sdk` — health, models, warm-up, file transcription, live sessions, metrics parsing.

### Browser SDK

`@voxd/client` — probe, transcribe, align, live sessions over the HTTP bridge.

### CLI

`@voxd/cli` — operator tool. Doctor, daemon lifecycle, model management, benchmarks, dashboards.

## Ownership

| Surface | Owns |
|---------|------|
| Swift runtime | Daemon lifecycle, audio prep, model lifecycle, transcription, perf recording |
| TypeScript SDK | Connection lifecycle, typed request/response shapes, live-session ergonomics, metric parsing |
| Browser SDK | Companion discovery, audio upload, job polling, live sessions over HTTP bridge |
| CLI | Operator commands, terminal output (human and machine), benchmarks, warm-up controls, dashboards |
| Site and docs | Architecture docs, onboarding, OG images, landing page |

## Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares audio and runs Parakeet
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection
