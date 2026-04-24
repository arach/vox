# Quickstart

## Prerequisites

- macOS 26+ or iOS 26+ for Apple SDK consumers
- Bun
- Swift 6.2+

## Install and verify

```bash
bun add -g @voxd/cli
vox daemon start
vox doctor       # expect ready: true
```

## Transcribe

```bash
vox warmup start
vox transcribe file /path/to/audio.wav --metrics --timestamps
```

First command warms the model to skip cold-start cost. Second transcribes a file and prints stage timings plus word-level timestamps.

## Measure and inspect

```bash
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard --client vox-cli
vox logs daemon --tail 80
vox transcribe status
```

`bench` runs five passes so you can see warm-path variance. `perf dashboard` shows latency samples by client, route, and model. Use `logs daemon` and `transcribe status` when a live session gets stuck or the mic is busy.

## Common failure cases

- Missing model: `vox models list` then `vox models install`
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a transcription first so the runtime emits samples
- Stuck live session: `vox transcribe status` then `vox transcribe cancel`
- Need daemon logs: `vox logs daemon --tail 120`

## Next steps

Try the [sample app](https://github.com/arach/vox/tree/main/examples/transcribe-tui) -- a terminal transcription tool that connects to the runtime, warms the model, and shows timing bars for each file.
