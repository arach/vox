# Quickstart

## Prerequisites

- macOS 14+
- Bun
- Swift 6.2+

## Install and verify

```bash
npx @vox-ai/cli install
vox daemon start
vox doctor
```

`doctor` confirms the daemon, model, and backend are healthy. You should see `ready: true`.

## Transcribe

```bash
vox warmup start
vox transcribe file /path/to/audio.wav --metrics
```

The first command warms the model so you skip cold-start cost. The second transcribes a file and prints stage timings alongside the text.

## Measure and inspect

```bash
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard --client vox-cli
```

`bench` runs five passes so you can see warm-path variance. `perf dashboard` shows latency samples tagged by client, route, and model.

## Common failure cases

- Missing model: `vox models list` then `vox models install`
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a transcription first so the runtime emits samples

## Next steps

Try the [sample app](https://github.com/arach/vox/tree/main/examples/transcribe-tui) — a terminal transcription tool that connects to the runtime, warms the model, and shows stage-level timing bars for every file you feed it.
