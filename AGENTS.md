# vox

> Local-first transcription runtime for macOS apps and developer tools

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- Always solve root cause before looking for workarounds and quick fixes.
- Vox is a macOS-first runtime: Swift owns the daemon and audio/transcription engine surface.
- The Bun workspace contains the CLI and TypeScript SDK, which communicate with voxd over local WebSocket JSON-RPC.
- Performance instrumentation is first-class: preserve clientId, route, and modelId dimensions in telemetry.
- Warm-up semantics are part of the public runtime surface and should remain usable for multi-client integrations.

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| Daemon | `swift/Sources/voxd/main.swift` | |
| Service | `swift/Sources/VoxService/` | |
| Engine | `swift/Sources/VoxEngine/` | |
| Core | `swift/Sources/VoxCore/` | |
| Sdk | `packages/client/src/` | |
| Cli | `packages/cli/src/index.ts` | |
| Docs | `docs/` | |
| Site | `site/` | |

## Quick Navigation

- Working with **swift/Sources/VoxEngine/***? → Keep instrumentation and model lifecycle explicit; do not hide warm-up cost in opaque helpers.
- Working with **swift/Sources/VoxService/***? → Preserve multi-client semantics; clientId should remain available anywhere latency or session ownership matters.
- Working with **packages/client/***? → SDK APIs should expose the runtime capabilities directly, including metrics and warm-up surfaces.
- Working with **packages/cli/***? → CLI commands are also operator tools; prefer clear terminal output and measurable benchmarks.
- Working with **site/***? → Maintain the clean, restrained Vox visual language. Avoid generic startup landing page patterns.

## Overview

Vox is a local-first transcription runtime for macOS, built as a Bun + SwiftPM monorepo.

Three public surfaces:

- `voxd` -- Swift daemon. Owns runtime state, warm-up, mic capture, transcription, telemetry.
- `@voxd/sdk` -- TypeScript SDK. Talks to the daemon over local WebSocket JSON-RPC.
- `vox` -- Bun CLI. Health checks, benchmarks, warm-up scheduling, transcription.

The runtime is split so that a menu bar app, browser extension, and editor plugin can all share one warm model instead of each loading its own.

## Common Workflows

```bash
# Build and verify
bun install && bun run build
bun packages/cli/src/index.ts doctor

# Warm the model
bun packages/cli/src/index.ts warmup start

# Transcribe and measure
bun packages/cli/src/index.ts transcribe file --metrics /tmp/sample.wav
bun packages/cli/src/index.ts transcribe bench /tmp/sample.wav 5
bun packages/cli/src/index.ts perf dashboard --client vox-cli
```

## Quickstart

Requirements: macOS 14+, Bun, Swift 6.2+.

```bash
git clone https://github.com/arach/vox.git && cd vox
bun install && bun run build
bun packages/cli/src/index.ts daemon start
bun packages/cli/src/index.ts doctor       # expect ready: true
```

Warm the model to skip cold-start cost, then transcribe:

```bash
bun packages/cli/src/index.ts warmup start
bun packages/cli/src/index.ts transcribe file /path/to/audio.wav
```

Troubleshooting:

- Missing model: `vox models list` then `vox models install`
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a transcription first so the runtime emits samples

## Runtime

Core flow:

1. Client connects to `voxd` over local WebSocket JSON-RPC.
2. Runtime resolves health, model state, and warm-up state.
3. Client triggers file transcription or a live session.
4. `VoxEngine` runs Parakeet locally, returns transcript text and stage metrics.
5. Runtime appends a tagged performance sample to `~/.vox/performance.jsonl`.

Warm-up is a public API, not a hidden side effect. Apps can warm on intent (`warmup.start`), schedule it ahead of time (`warmup.schedule`), or check if the model is already hot (`warmup.status`).

`transcribe.file` is the best path for benchmarks because it removes mic capture from the measurement.

Route names (`transcribe.file`, `transcribe.startSession`, `warmup.start`, etc.) double as telemetry dimensions. Do not rename them.

Live sessions: one at a time, owned by `connectionID` + `clientId`, explicit stop/cancel semantics.

Key Swift entry points:

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ParakeetProvider.swift`

## SDK

`packages/client/` -- TypeScript SDK for talking to the daemon.

Connects to the local runtime, manages models and warm-up, transcribes files, creates live sessions, and returns stage metrics.

### Example

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const result = await client.transcribeFile("/tmp/sample.wav");

console.log(result.text);
console.log(result.metrics?.inferenceMs);

client.disconnect();
```

`clientId` is used to attribute latency by consumer, compare route-level behavior across integrations, and support multi-client workflows.

### Methods

```ts
interface VoxClientSurface {
  connect(): Promise<void>;
  disconnect(): void;
  doctor(): Promise<unknown>;
  listModels(): Promise<unknown>;
  installModel(modelId?: string): Promise<unknown>;
  preloadModel(modelId?: string): Promise<unknown>;
  getWarmupStatus(modelId?: string): Promise<unknown>;
  startWarmup(modelId?: string): Promise<unknown>;
  scheduleWarmup(modelId?: string, delayMs?: number): Promise<unknown>;
  transcribeFile(path: string): Promise<FileTranscriptionResult>;
  createLiveSession(): Promise<unknown>;
}
```

### File result shape

```ts
interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
}
```

### Integration tips

- Use a stable `clientId` per product surface: `menu-bar`, `browser-extension`, `vox-cli`.
- Warm on intent, not on every keystroke.
- Read `inferenceMs` separately from `totalMs` when benchmarking.
- Forward raw metrics to your own telemetry if the app already exports traces.

## Observability

Telemetry is built into the runtime, not bolted on.

Each performance sample is tagged with:

- `clientId`
- `route`
- `modelId`

Recorded metrics:

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Derived: `realtimeFactor`, warm vs cold from `modelLoadMs`, audio-to-text speed from `audioDurationMs / inferenceMs`.

Samples are appended as JSON lines to `~/.vox/performance.jsonl`. The CLI dashboard reads from this file.

### Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

`inferenceMs` = how fast the hot model is. `totalMs` = what the user experienced. They measure different things.

### Example sample

```json
{
  "clientId": "menu-bar",
  "route": "transcribe.file",
  "modelId": "parakeet:v3",
  "audioDurationMs": 5110,
  "inferenceMs": 151,
  "totalMs": 165
}
```

### Reading the dashboard

- Only compare clients when the audio is similar.
- `inferenceMs` = loaded-model speed. `totalMs` = end-user latency.
- Large `modelLoadMs` spikes are warm-up events, not inference regressions.

## Architecture

| Layer | What it does |
|-------|-------------|
| **VoxCore** | Shared types: runtime metadata, metrics, performance samples, filesystem paths, trace utilities |
| **VoxEngine** | Model layer: install, preload, audio prep, Parakeet inference, stage timing |
| **VoxService** | Daemon orchestration: JSON-RPC bridge, live sessions, mic recording, warm-up, perf recording |
| **@voxd/sdk** | TypeScript client: health, models, warm-up, file transcription, live sessions, metrics |
| **vox CLI** | Operator tool: doctor, daemon lifecycle, model management, benchmarks, dashboards |

### Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares audio and runs Parakeet
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection

## API

Public protocol and SDK-facing shapes.

## RPC Methods

### Health and Runtime

- `health`
- `doctor.run`

### Models

- `models.list`
- `models.install`
- `models.preload`

### Warm-Up

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

### Transcription

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.stopSession`
- `transcribe.cancelSession`

### Stable dimensions

These are present on every performance sample and must not be dropped:

```ts
type VoxRoute =
  | "transcribe.file"
  | "transcribe.startSession"
  | "transcribe.stopSession"
  | "transcribe.cancelSession"
  | "warmup.status"
  | "warmup.start"
  | "warmup.schedule";
```

```ts
interface PerformanceSample {
  clientId: string;
  route: VoxRoute | string;
  modelId: string;
  audioDurationMs?: number;
  inferenceMs?: number;
  totalMs?: number;
}
```

### TypeScript SDK Entry Points

**`VoxClient`**

- `connect()`
- `disconnect()`
- `doctor()`
- `listModels()`
- `installModel()`
- `preloadModel()`
- `getWarmupStatus()`
- `startWarmup()`
- `scheduleWarmup()`
- `transcribeFile()`
- `createLiveSession()`

**`FileTranscriptionResult`**

- `modelId`
- `text`
- `elapsedMs`
- `metrics`

**`TranscriptionMetrics`**

- `traceId`
- `audioDurationMs`
- `inputBytes`
- `wasPreloaded`
- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `realtimeFactor`

### Interface shapes

```ts
interface TranscriptionMetrics {
  traceId: string;
  audioDurationMs?: number;
  inputBytes?: number;
  wasPreloaded?: boolean;
  fileCheckMs?: number;
  modelCheckMs?: number;
  modelLoadMs?: number;
  audioLoadMs?: number;
  audioPrepareMs?: number;
  inferenceMs?: number;
  totalMs?: number;
  realtimeFactor?: number;
}

interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
}
```

### Warm-up states

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

Apps use this to tell whether the runtime is cold, warming, or ready for hot-path transcription.

---
Generated by [Dewey 0.3.4](https://github.com/arach/dewey) | Last updated: 2026-03-17