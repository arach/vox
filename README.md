# Vox

Vox is a local-first transcription runtime for macOS, built as a Bun + SwiftPM monorepo.

- `voxd` -- Swift daemon. Owns model state, transcription, warm-up, and telemetry.
- `@voxd/sdk` -- TypeScript SDK. Typed JSON-RPC client for app integrations.
- `vox` -- Bun CLI. Health checks, benchmarks, warm-up scheduling, dashboards.

A menu bar app, browser extension, and editor plugin can all share one warm runtime instead of each loading their own model.

## Layout

- `swift/` contains `VoxCore`, `VoxEngine`, `VoxService`, and the `voxd` daemon.
- `packages/client` contains the TypeScript SDK for talking to the daemon over local WebSocket JSON-RPC.
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

Each transcription appends a tagged sample to `~/.vox/performance.jsonl` with `clientId`, `route`, and `modelId`.

You can answer: is the hot model fast? Which integration is regressing? Is latency in inference, audio prep, or cold runtime work?

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

## Runtime

- Runtime discovery: `~/.vox/runtime.json`
- Latency samples: `~/.vox/performance.jsonl`
- Daemon logs: `~/.vox/logs/voxd.log` (written even when `voxd` is auto-started by the CLI)

`bun run test:e2e` is an opt-in macOS integration suite. It boots `voxd`, preloads the model, synthesizes speech with `say`, and checks `transcribe file` output against keyword expectations.

## Docs and site

- Dewey source docs: `docs/`
- Generated handoff files: `AGENTS.md`, `llms.txt`, `docs.json`, `install.md`
- Website and `/docs` route: `site/`
- OG image template: `site/og-template.html`

## Release automation

- GitHub Pages deploys from `.github/workflows/deploy-pages.yml` to `https://voxd.cc`
- npm publishing runs from `.github/workflows/publish-packages.yml`, publishes `@voxd/sdk` before `@voxd/cli`
