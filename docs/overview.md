# Vox Overview

Vox is a local-first transcription runtime for macOS. Three surfaces:

- `voxd` — Swift daemon. Runtime state, warm-up, mic capture, transcription, telemetry.
- `@voxd/sdk` — TypeScript SDK for native apps and Bun/Node. WebSocket JSON-RPC to the daemon.
- `@voxd/client` — Browser SDK. HTTP bridge to the Vox Companion for web apps.
- `@voxd/cli` — Bun CLI. Health checks, benchmarks, warm-up, transcription.

## Why it exists

Most transcription tools hide the runtime. Vox exposes it:

- Model stays local
- Warm-up is an explicit API
- Latency dimensions (`clientId`, `route`, `modelId`) are preserved
- Runtime is observable from day one

## Repository layout

- `swift/` — VoxCore, VoxEngine, VoxService, voxd daemon
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

App teams embed `@voxd/sdk` (native) or `@voxd/client` (browser) and keep their `clientId`. Operators use `vox` CLI to check health, warm-up, and performance. The daemon stays warm across menu bar apps, browser extensions, editor plugins, and the CLI — no duplicate model loads.

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
