---
title: Architecture
description: Layer ownership and data flow across Swift engines, companion transports, TypeScript clients, and operator tools.
---

## Layers

### VoxCore

Shared runtime types and utilities:

- runtime metadata
- transcription and synthesis metrics
- performance samples
- filesystem paths
- trace utilities

### VoxEngine

Model-facing speech layer:

- model installation and preload
- ASR provider routing and audio preparation
- annotation provider routing and speaker-attribution contracts
- TTS provider routing and voice discovery
- Parakeet inference
- AVSpeech, OpenAI, and external synthesis backends
- stage-level timing

### VoxAppleSpeech

Optional Apple embed playback layer:

- per-audible-surface speech output controller
- live system delivery for `avspeech:system`
- generated-audio playback through an injectable sink
- typed playback phases without app product policy

### VoxService

Daemon-side orchestration:

- JSON-RPC bridge
- annotation route dispatch
- live session coordination
- synthesis session coordination
- microphone recording
- warm-up scheduling
- performance sample recording

### TypeScript SDK

`@voxd/sdk`: health, models, voices, warm-up, file transcription, synthesis, live sessions, metrics parsing.

### Browser SDK

`@voxd/client`: probe, transcribe, align, live sessions over the HTTP bridge.

### Companion bridge

`VoxBridge` / `voxbridge`: browser-facing HTTP bridge that proxies into the companion daemon while keeping the browser surface narrower than the underlying WebSocket RPC runtime.

### CLI

`@voxd/cli`: operator tool. Doctor, daemon lifecycle, model management, voices, transcription, synthesis, benchmarks, dashboards.

## Ownership

| Surface | Owns |
|---------|------|
| Swift runtime | Daemon lifecycle, audio prep, model lifecycle, provider routing, transcription, annotation, synthesis, perf recording |
| TypeScript SDK | Connection lifecycle, typed request/response shapes, live-session ergonomics, transcription and synthesis metric parsing |
| Browser SDK | Companion discovery, audio upload, job polling, live sessions over HTTP bridge |
| CLI | Operator commands, terminal output (human and machine), warm-up controls, transcription, synthesis, dashboards |
| Site and docs | Architecture docs, onboarding, OG images, landing page |

## Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`, while browser clients reach the same runtime through `VoxBridge`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares ASR input, annotation input, or TTS requests and dispatches them to the selected provider
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection

```text
Apple app ───────────────▶ VoxEngine
Bun/Node tool ─▶ voxd ──▶ VoxService ─▶ VoxEngine
Browser ───────▶ VoxBridge ─▶ voxd ───▶ VoxService ─▶ VoxEngine
```

See [Runtime](./runtime.md) for route-level behavior and [Provider Protocol](./providers.md) for external engine boundaries.
