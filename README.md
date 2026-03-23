# Vox

Vox is a macOS-first local transcription runtime built as a Bun + SwiftPM monorepo.

It is designed for developers who want transcription as infrastructure:

- Swift services for the local runtime
- a Bun CLI for operator workflows
- a TypeScript SDK for app integrations
- explicit warm-up semantics
- latency and throughput visibility by client, route, and model

## Why It Exists

Most transcription products expose one narrow SDK surface and hide the runtime behind it.
Vox makes the runtime explicit instead:

- `voxd` owns local model state, transcription, warm-up, and telemetry
- `@vox/client` gives apps a typed JSON-RPC integration surface
- `vox` gives operators a local tool for health checks, benchmarks, and dashboards

That split makes it easier to build multi-client products where a menu bar app, browser extension, or editor plugin can all talk to the same warm runtime.

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

## What You Can Measure

Vox records stage-level metrics for each transcription and appends tagged samples to `~/.vox/performance.jsonl`.

Those samples keep these dimensions intact:

- `clientId`
- `route`
- `modelId`

That lets you answer practical questions quickly:

- Is the hot model actually fast?
- Which integration surface is regressing?
- Is user-visible latency in inference, audio preparation, or cold runtime work?

### CLI examples

```bash
vox daemon start
vox doctor
vox models list
vox models install
vox warmup start
vox warmup schedule 500
vox transcribe file --timestamps /path/to/audio.wav
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard
vox transcribe live --timestamps
```

## Runtime

The daemon writes runtime discovery metadata to `~/.vox/runtime.json`.
Tagged latency samples are appended to `~/.vox/performance.jsonl`.

`bun run test:e2e` is an opt-in macOS integration suite. It boots `voxd`, preloads the model, synthesizes short speech samples with `say`, and verifies real `transcribe file` output against keyword checks.

## Docs And Site

- Dewey source docs live in `docs/`
- generated handoff files include `AGENTS.md`, `llms.txt`, `docs.json`, and `install.md`
- the website and `/docs` experience live in `site/`
- the OG image is generated from `site/og-template.html`

## Release Automation

- GitHub Pages deploys from [`.github/workflows/deploy-pages.yml`](/Users/arach/dev/vox/.github/workflows/deploy-pages.yml) to `https://voxd.cc`
- npm publishing runs from [`.github/workflows/publish-packages.yml`](/Users/arach/dev/vox/.github/workflows/publish-packages.yml) and publishes `@vox/client` before `@vox/cli`
