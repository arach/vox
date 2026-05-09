# Vox

Vox is a local-first voice stack for Apple platforms. This repo brings together the Hudson-powered menu bar app, the Swift runtime, the companion daemon, the TypeScript clients, and the CLI.

- `VoxCore`, `VoxEngine`, `VoxService`, and `VoxBridge`: embeddable Swift packages for macOS and iOS apps.
- `voxd`: Vox Companion, the Swift daemon for web-facing, shared-process, and operator integrations.
- `@voxd/sdk`: TypeScript SDK. Typed JSON-RPC client for Vox Companion integrations.
- `@voxd/client`: Browser SDK. HTTP bridge client for local web integrations.
- `vox`: Node CLI. Health checks, benchmarks, warm-up scheduling, dashboards.
- `Vox.app`: Hudson-based macOS menu bar app, packaged as a signed and notarized DMG by release automation.

Apple apps can embed Vox directly. Bun and Node tools can connect to `voxd` over local WebSocket JSON-RPC. Browser clients can connect through the companion HTTP bridge with `@voxd/client`.

## Pick a surface

- Build a native Apple app: start with `VoxCore`, `VoxEngine`, `VoxService`, and `VoxBridge`.
- Build a local tool or companion-connected service: start with `voxd` plus `@voxd/sdk`.
- Build a browser integration: start with `@voxd/client` plus the local bridge path.
- Operate or benchmark Vox itself: start with the `vox` CLI.

## Get Going Fast

Requirements:

- macOS 26+
- Bun 1.2+
- Node 22+
- Swift 6.2+
- `uv` for the MLX-backed demo paths

### a. dev

To work on Vox:

```bash
git clone https://github.com/arach/vox.git
cd vox
bun install
bun run build
bun run test
```

Useful loops:

```bash
bun run site:dev
bun run docs:build
swift build --package-path swift
```

### b. client

To use Vox Companion locally from the CLI or SDK:

```bash
git clone https://github.com/arach/vox.git
cd vox
bun install
bun run build
```

Start the daemon, verify health, then transcribe:

```bash
node packages/cli/dist/index.js daemon start
node packages/cli/dist/index.js doctor
node packages/cli/dist/index.js models preload parakeet:v3
node packages/cli/dist/index.js transcribe file /path/to/audio.wav
```

If you are writing a local client, start here:

- `packages/client/` for the TypeScript SDK
- `packages/web-client/` for the browser SDK
- `swift/` for direct Apple embed mode

### c. demo

To run the standalone macOS demo app:

```bash
git clone https://github.com/arach/vox.git
cd vox
bun install
swift run --package-path examples/macos-minimal VoxMinimalExample
```

What the demo does:

- records locally from the mic
- transcribes with Parakeet
- replies with Apple Intelligence when available
- falls back to local Qwen 0.6B when Apple Intelligence is not ready
- speaks back with Kokoro through the MLX audio provider

Notes:

- The first run may download Parakeet, Kokoro, or the Qwen fallback model.
- The app will ask for microphone access.
- Apple Intelligence is optional for the demo, not required.

The current standalone demo lives in `examples/macos-minimal/` and is a good reference app for direct embed mode.

## Layout

- `swift/` contains `VoxCore`, `VoxEngine`, `VoxService`, and the `voxd` daemon.
- `packages/client` contains the TypeScript SDK for talking to `voxd` over local WebSocket JSON-RPC.
- `packages/web-client` contains the browser SDK for talking to the local HTTP bridge.
- `packages/cli` contains the `vox` CLI.
- `docs/` contains Dewey source docs.
- `site/` contains the marketing site, docs route, and OG generation.

## Commands

```bash
bun install
bun run dev
bun run build
bun run build:all
bun run test
bun run test:e2e
bun run site:build
bun run site:og
bun run docs:generate
```

## Telemetry

Each transcription or synthesis request appends a tagged sample to `~/.vox/performance.jsonl` with `clientId`, `route`, `modelId`, and `voiceId` when applicable.

This lets you answer a few practical questions: is the hot model fast, which integration is regressing, and whether latency is in inference, audio prep, or cold runtime work.

### CLI

```bash
vox daemon start
vox doctor
vox models list
vox models install
vox warmup start
vox warmup schedule 500
vox logs daemon --tail 80
vox transcribe status
vox transcribe cancel
vox transcribe file --timestamps /path/to/audio.wav
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard
vox transcribe live --timestamps
```

## Companion Runtime

- Runtime discovery: `~/.vox/runtime.json`
- Latency samples: `~/.vox/performance.jsonl`
- Daemon logs: `~/.vox/logs/voxd.log` (written even when `voxd` is auto-started by the CLI)

`voxd` is Vox Companion: the shared-process and web-facing transport for Vox. `bun run test:e2e` is an opt-in macOS integration suite that boots `voxd`, preloads the model, synthesizes speech with `say`, and checks `transcribe file` output against keyword expectations.

Speech synthesis supports Apple system voices locally and OpenAI TTS (`gpt-4o-mini-tts`, `tts-1`, and `tts-1-hd`) when `OPENAI_API_KEY` is configured. The packaged app bundles `voxd` and `voxttsd` so the menu bar app and CLI share the same companion runtime.

## Docs and site

- Dewey source docs: `docs/`
- Generated handoff files: `AGENTS.md`, `llms.txt`, `docs.json`, `install.md`
- Website and `/docs` route: `site/`
- OG image template: `site/og-template.html`

## Release automation

- GitHub Pages deploys from `.github/workflows/deploy-pages.yml` to `https://voxd.cc`
- npm publishing runs from `.github/workflows/publish-packages.yml` on `v*` tags and publishes `@voxd/sdk`, `@voxd/client`, and `@voxd/cli`
- DMG builds run from `.github/workflows/release-dmg.yml`. Tag builds create or update the matching GitHub Release and upload `Vox.dmg`.
- Manual DMG releases can be started from the workflow page with a version. The workflow validates the repo versions, builds the DMG, signs and notarizes it, creates `v<version>` when needed, creates the GitHub Release, and uploads the installer.

Required release secrets:

- `APPLE_SIGNING_CERT_BASE64`
- `APPLE_SIGNING_CERT_PASSWORD`
- `APPLE_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_PASSWORD`
- `APPLE_TEAM_ID`
- `NPM_TOKEN` for package publishing
