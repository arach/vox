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
