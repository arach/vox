# Vox Overview

Vox is a local-first voice stack for macOS and iOS. It supports two first-class integration modes:

- Embed mode -- Apple apps link Vox's Swift packages directly and keep voice in and voice out in process.
- Companion mode -- `voxd` exposes the same capabilities over local JSON-RPC and HTTP when web or shared-process access is useful.

Main surfaces:

- Swift packages -- `VoxCore`, `VoxEngine`, `VoxService`, `VoxBridge` for embedded Apple app integrations.
- `voxd` -- Vox Companion, the Swift daemon. Warm-up, telemetry, bridge transport, shared-process coordination.
- `@voxd/sdk` -- TypeScript SDK for Bun/Node and other companion-connected integrations.
- `vox` -- Bun CLI. Health checks, benchmarks, warm-up scheduling, transcription, synthesis.

## Why it exists

Most voice stacks hide lifecycle, warm-up, and latency. Vox keeps them visible:

- Model stays local
- Warm-up is an explicit API
- Latency dimensions (`clientId`, `route`, `modelId`) are preserved
- Runtime is observable from day one

## Repository layout

- `swift/` -- VoxCore, VoxEngine, VoxService, VoxBridge, voxd companion
- `packages/client/` -- TypeScript SDK
- `packages/cli/` -- Bun CLI
- `docs/` -- Dewey source content
- `site/` -- website, docs route, OG generation

## Design principles

1. Root cause over workaround.
2. Warm-up is part of the product, not an implementation detail.
3. Instrumentation is part of the API surface.
4. Multi-client support stays visible in the protocol and telemetry.

## How it fits together

The split between embed and companion surfaces is intentional. Apple apps embed the Swift packages directly and keep the same provider, warm-up, and telemetry semantics in process. Web apps use `@voxd/client` against Vox Companion, and operators use `vox` to check health, warm-up, and performance. Companion mode lets `voxd` stay warm across browser integrations, local tools, and other shared-process clients.

## Workflows

```bash
# Build and verify
bun install && bun run build
bun packages/cli/src/index.ts doctor

# Warm the model before speech
bun packages/cli/src/index.ts warmup start
bun packages/cli/src/index.ts warmup schedule 500 parakeet:v3

# Transcribe and measure
bun packages/cli/src/index.ts transcribe file --metrics /tmp/sample.wav
bun packages/cli/src/index.ts transcribe bench /tmp/sample.wav 5
bun packages/cli/src/index.ts perf dashboard --client vox-cli
```
