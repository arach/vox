# Vox Overview

Vox is a local-first transcription runtime for macOS. It runs as a Bun + SwiftPM monorepo with three surfaces:

- `voxd` -- Swift daemon. Owns runtime state, warm-up, mic capture, transcription, and telemetry.
- `@voxd/sdk` -- TypeScript SDK. Talks to the daemon over local WebSocket JSON-RPC.
- `vox` -- Bun CLI. Health checks, benchmarks, warm-up scheduling, transcription.

## Why it exists

Most transcription tools hide the runtime. Vox exposes it:

- Model stays local
- Warm-up is an explicit API
- Latency dimensions (`clientId`, `route`, `modelId`) are preserved
- Runtime is observable from day one

## Repository layout

- `swift/` -- VoxCore, VoxEngine, VoxService, voxd daemon
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

The split between operator and integration surfaces is intentional. App teams embed `@voxd/sdk` and keep their `clientId`. Operators use `vox` to check health, warm-up, and performance. The daemon stays warm across menu bar apps, browser extensions, editor plugins, and the CLI -- no duplicate model loads.

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
