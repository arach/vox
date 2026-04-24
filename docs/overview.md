# Vox Overview

Vox is a local-first voice stack for macOS and iOS. Two first-class integration modes:

- Embed mode — Apple apps link Vox's Swift packages directly and keep voice in and voice out in process.
- Companion mode — `voxd` exposes the same capabilities over local JSON-RPC and HTTP when web or shared-process access is useful.

Main surfaces:

- Swift packages — `VoxCore`, `VoxEngine`, `VoxService`, `VoxBridge` for embedded Apple app integrations.
- `voxd` — Vox Companion, the Swift daemon. Warm-up, telemetry, bridge transport, shared-process coordination.
- `@voxd/sdk` — TypeScript SDK for Bun/Node and other companion-connected integrations. WebSocket JSON-RPC to `voxd`.
- `@voxd/client` — Browser SDK. HTTP bridge to the Vox Companion for web apps.
- `@voxd/cli` — Bun CLI. Health checks, benchmarks, warm-up, transcription.

## Why it exists

Most voice stacks hide lifecycle, warm-up, and latency. Vox keeps them visible:

- Model stays local
- Warm-up is an explicit API
- Latency dimensions (`clientId`, `route`, `modelId`) are preserved
- Runtime is observable from day one

## Repository layout

- `swift/` — VoxCore, VoxEngine, VoxService, VoxBridge, voxd companion
- `packages/client/` — `@voxd/sdk` (TypeScript SDK)
- `packages/web-client/` — `@voxd/client` (browser SDK)
- `packages/cli/` — `@voxd/cli` (Bun CLI)
- `docs/` — Dewey source content
- `site/` — website and docs UI

## Design principles

1. Root cause over workaround.
2. Warm-up is part of the product, not an implementation detail.
3. Instrumentation is part of the API surface.
4. Multi-client support stays visible in the protocol and telemetry.

## How it fits together

Apple app teams embed the Swift packages directly and keep the same provider, warm-up, and telemetry semantics in process. Web apps use `@voxd/client` against Vox Companion, Bun and Node tools use `@voxd/sdk`, and operators use `vox` CLI to check health, warm-up, and performance. Companion mode lets `voxd` stay warm across browser integrations, local tools, and other shared-process clients.

## Workflows

```bash
# Build and verify
bun install && bun run build
vox doctor

# Warm the model before speech
vox warmup start
vox warmup schedule 500 parakeet:v3

# Transcribe and measure
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox perf dashboard --client vox-cli
```
