# Quickstart

## Prerequisites

- macOS 26+ or iOS 26+ for Apple SDK consumers
- Bun
- Swift 6.2+

## Clone, build, verify

```bash
git clone https://github.com/arach/vox.git && cd vox
bun install && bun run build
vox daemon start
vox doctor       # expect ready: true
```

## Transcribe

```bash
vox warmup start
vox transcribe file /path/to/audio.wav --metrics
```

First command warms the model to skip cold-start cost. Second transcribes a file and prints stage timings alongside the text.

## Measure and inspect

```bash
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard --client vox-cli
```

`bench` runs five passes so you can see warm-path variance. `perf dashboard` shows latency samples by client, route, and model.

## Common failure cases

- Missing model: `vox models list` then `vox models install`
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a transcription first so the runtime emits samples

## Next steps

Try the [sample app](https://github.com/arach/vox/tree/main/examples/transcribe-tui) -- a terminal transcription tool that connects to the runtime, warms the model, and shows timing bars for each file.
