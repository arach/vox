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

# Vox Overview

Vox is a local-first transcription runtime for macOS.

It is built as a Bun + SwiftPM monorepo with three public surfaces:

- `voxd` — the standalone Swift daemon that owns runtime state, warm-up, microphone capture, transcription, and telemetry.
- `@vox/client` — the TypeScript SDK for talking to the daemon over local WebSocket JSON-RPC.
- `vox` — the Bun CLI for operator workflows like health checks, benchmarks, warm-up scheduling, and local transcription.

## Why Vox Exists

Most transcription integrations hide the runtime behind a black box. Vox takes the opposite approach:

- keep the model local
- expose warm-up as an explicit capability
- preserve latency dimensions like `clientId`, `route`, and `modelId`
- make the runtime observable from day one

## Repository Structure

- `swift/` — `VoxCore`, `VoxEngine`, `VoxService`, and the `voxd` daemon entrypoint
- `packages/client/` — TypeScript SDK
- `packages/cli/` — Bun CLI
- `docs/` — Dewey source content
- `site/` — landing page, docs route, and OG generation

## Design Principles

1. Root cause over workaround.
2. Warm-up is part of the product, not an implementation accident.
3. Instrumentation is part of the API surface.
4. Multi-client support should remain visible in the protocol and telemetry.

## What Makes Vox Different

Vox is intentionally split into operator and integration surfaces:

- app teams can embed `@vox/client` and preserve `clientId`
- operators can use `vox` to inspect health, warm-up, and performance
- the daemon can stay warm across multiple consumers instead of each app loading its own model

That makes Vox a better fit for developer tools and desktop workflows than a single-purpose SDK that hides the runtime lifecycle.

## Primary Workflows

### Build and verify the runtime

```bash
bun install
bun run build
bun packages/cli/src/index.ts doctor
```

### Warm the model before expected speech

```bash
bun packages/cli/src/index.ts warmup start
bun packages/cli/src/index.ts warmup schedule 500 parakeet:v3
```

### Measure real transcription performance

```bash
bun packages/cli/src/index.ts transcribe file --metrics /tmp/sample.wav
bun packages/cli/src/index.ts transcribe bench /tmp/sample.wav 5
bun packages/cli/src/index.ts perf dashboard --client vox-cli
```

## Public Repository Goals

This repository should be useful to three audiences:

- developers integrating local transcription into macOS apps
- operators benchmarking warm-path performance and runtime health
- other contributors extending the Swift runtime, CLI, or SDK without losing observability

## Quickstart

# Quickstart

## Prerequisites

- macOS 14+
- Bun
- Swift 6.2+

## Install

```bash
git clone https://github.com/arach/vox.git
cd vox
bun install
```

## Build

```bash
bun run build
```

## Start the daemon

```bash
bun packages/cli/src/index.ts daemon start
```

## Verify

```bash
bun packages/cli/src/index.ts doctor
```

Expected healthy output includes:

- `ready: true`
- `runtime`
- `backend`
- `model`

## Try File Transcription

```bash
bun packages/cli/src/index.ts transcribe file /path/to/audio.wav
```

If you want to avoid cold-start model cost before the first real request:

```bash
bun packages/cli/src/index.ts warmup start
```

## Measure Warm Performance

```bash
bun packages/cli/src/index.ts transcribe bench /path/to/audio.wav 5
```

## Inspect Telemetry

```bash
bun packages/cli/src/index.ts perf dashboard
```

## Typical healthy flow

1. `doctor` reports `ready: true`
2. `warmup status` reports that Parakeet is ready or warming
3. `transcribe file` returns transcript text and optional metrics
4. `perf dashboard` shows samples tagged with your `clientId`

## Common failure cases

- Missing model: run `vox models list` and `vox models install`
- Cold runtime: issue `warmup start` or `warmup schedule`
- No performance data: run a transcription command first so the runtime emits samples

## Runtime

# Runtime

## Core Flow

1. A client connects to `voxd` over local WebSocket JSON-RPC.
2. The runtime resolves health, model state, and optional warm-up state.
3. The client triggers file transcription or a live session.
4. `VoxEngine` runs Parakeet locally and returns transcript text plus stage metrics.
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
- final transcript events include metrics

## Important Swift entry points

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ParakeetProvider.swift`

## Sdk

# SDK

The TypeScript SDK lives in `packages/client/`.

## Main Capabilities

- connect to the local runtime
- inspect health and doctor checks
- list/install/preload models
- start and schedule warm-up
- transcribe files
- create live sessions
- receive stage metrics on transcription results

## Example

```ts
import { VoxClient } from "@vox/client";

const client = new VoxClient({ clientId: "raycast" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const result = await client.transcribeFile("/tmp/sample.wav");

console.log(result.text);
console.log(result.metrics?.inferenceMs);

client.disconnect();
```

## Client Identity

`clientId` matters.

It is used by the runtime to:

- attribute latency by consumer
- inspect route-level behavior across integrations
- support multi-client operator workflows

## Main methods

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

## File result shape

```ts
interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
}
```

## Integration advice

- use a stable `clientId` per product surface such as `raycast`, `browser-extension`, or `vox-cli`
- warm on intent, not on every keystroke
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve the raw metrics in your own telemetry if the app already exports traces

## Observability

# Observability

Vox treats transcription telemetry as a first-class runtime feature.

## Dimensions

Each performance sample is tagged with:

- `clientId`
- `route`
- `modelId`

## Metrics

Current metrics include:

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Additional useful derived values:

- `realtimeFactor`
- warm vs cold path behavior from `modelLoadMs`
- effective audio-to-text speed from `audioDurationMs / inferenceMs`

## Storage

The runtime appends JSON lines to:

```text
~/.vox/performance.jsonl
```

That local store powers the CLI dashboard today and can later be exported to another metrics backend if needed.

## Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

## Philosophy

Loaded-model inference speed and end-to-end latency are different things.

Vox records both:

- `inferenceMs` tells you how fast the hot model is.
- `totalMs` tells you what the user actually experienced.

## Example sample

```json
{
  "clientId": "raycast",
  "route": "transcribe.file",
  "modelId": "parakeet:v3",
  "audioDurationMs": 5110,
  "inferenceMs": 151,
  "totalMs": 165
}
```

## How to read the dashboard

- Compare clients against each other only when the audio shape is similar
- Use `inferenceMs` to judge loaded-model speed
- Use `totalMs` to judge end-user experience
- Treat large `modelLoadMs` spikes as warm-up lifecycle events, not steady-state inference regressions

## Architecture

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

`@vox/client` mirrors the runtime capabilities for integrations:

- health
- models
- warm-up
- file transcription
- live sessions
- metrics parsing

### CLI

`vox` is both an operator tool and a dogfooding surface:

- doctor and daemon lifecycle
- model management
- warm benchmarks
- metrics inspection
- dashboard views

## Public Surfaces

- `voxd`
- `@vox/client`
- `vox`
- `site/`

## Responsibility Boundaries

### Swift runtime

Owns:

- daemon lifecycle
- audio loading and preparation
- model lifecycle
- transcription execution
- performance sample recording

### TypeScript SDK

Owns:

- connection lifecycle to the local daemon
- typed request and response shapes
- live-session client ergonomics
- metric parsing for JS and TS consumers

### CLI

Owns:

- operator-facing commands
- machine-readable and human-readable terminal output
- benchmarks, warm-up controls, and dashboard inspection

### Site and docs

Own:

- public explanation of the architecture
- onboarding for contributors and integrators
- OG, landing, and `/docs` presentation

## Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares audio and runs Parakeet
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection

## Api

# API

This page describes the public protocol and SDK-facing shapes that other apps should rely on.

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

## Stable dimensions

These values should remain available anywhere the runtime records or returns performance information:

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

## Core TypeScript SDK Entry Points

### `VoxClient`

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

### `FileTranscriptionResult`

- `modelId`
- `text`
- `elapsedMs`
- `metrics`

### `TranscriptionMetrics`

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

## Interface shapes

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

## Warm-up response expectations

Warm-up APIs should make these states observable:

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

That state is useful to apps because it lets them distinguish:

- a runtime that has not been asked to warm
- a runtime that is actively warming
- a runtime that is ready for hot-path transcription

---
Generated by [Dewey 0.3.4](https://github.com/arach/dewey) | Last updated: 2026-03-17