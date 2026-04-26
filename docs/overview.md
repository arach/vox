# Vox Overview

Vox is a local-first voice stack for macOS and iOS. It supports both speech-to-text (STT / ASR) and text-to-speech (TTS) in two first-class integration modes:

- Embed mode — Apple apps link Vox's Swift packages directly and keep speech in and speech out in process.
- Companion mode — `voxd` exposes the runtime over local WebSocket JSON-RPC, and `VoxBridge` / `voxbridge` exposes an HTTP bridge for browser clients when web or shared-process access is useful.

Main surfaces:

- Swift packages — `VoxCore`, `VoxEngine`, `VoxService`, `VoxBridge` for embedded Apple app integrations.
- `voxd` — Vox Companion, the Swift daemon. Warm-up, telemetry, bridge transport, shared-process coordination.
- `@voxd/sdk` — TypeScript SDK for Bun/Node and other companion-connected integrations. WebSocket JSON-RPC to `voxd`.
- `@voxd/client` — Browser SDK. HTTP bridge to the Vox Companion for web apps.
- `@voxd/cli` — Bun CLI. Health checks, model management, transcription, synthesis, voices, warm-up, and benchmarks.

## Which surface to reach for

- Use the Swift packages when you are modifying a macOS or iOS app and want speech to stay in process.
- Use `@voxd/sdk` when you want a local Bun or Node client to talk to the companion daemon over WebSocket JSON-RPC.
- Use `@voxd/client` when you want a browser app to talk to the local HTTP bridge on the same Mac.
- Use `@voxd/cli` when you want operator commands, warm-up controls, voice listing, or reproducible benchmarks.

## Why it exists

Most voice stacks hide lifecycle, warm-up, and latency. Vox keeps them visible:

- Model stays local
- STT and TTS stay explicit runtime capabilities instead of hidden backend switches
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

Apple app teams embed the Swift packages directly and keep the same provider, warm-up, and telemetry semantics in process. Bun and Node tools use `@voxd/sdk` against `voxd`, browser apps use `@voxd/client` against the local HTTP bridge, and operators use `vox` to check health, list voices, transcribe, synthesize, warm models, and benchmark both speech paths. Companion mode lets `voxd` stay warm across browser integrations, local tools, and other shared-process clients while the bridge stays narrow and browser-facing.

## Reference implementations

- `examples/macos-minimal/` is the best standalone reference for the direct Apple embed path.
- `packages/client/` and `packages/web-client/` are the clearest companion-mode SDK surfaces in the repo.

## Workflows

These examples assume `vox` is on your `PATH`. In a repo checkout, replace `vox` with `bun packages/cli/src/index.ts`.

```bash
# Build and verify
bun install && bun run build
vox daemon start
vox doctor

# Speech to text
vox warmup start parakeet:v3
vox transcribe file --model parakeet:v3 --metrics --timestamps /tmp/sample.wav

# Text to speech
vox voices --model avspeech:system
vox speak --model avspeech:system --metrics "Hello from Vox"

# Compare warm-path performance
vox transcribe bench --model parakeet:v3 /tmp/sample.wav 5
vox speak bench --model avspeech:system "Hello from Vox" 5
vox perf dashboard --client vox-cli
```
