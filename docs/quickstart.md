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
