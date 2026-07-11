---
title: Operations Guide
description: Repeatable health, warm-up, benchmark, and performance-triage workflows for operators and agents.
audience: agent
---

Highest-value workflows:

- add warm-up before first speech
- preserve `clientId` in SDK initialization
- benchmark warm performance with real audio
- read the local dashboard before speculating about latency

Recommended operator loop:

```bash
vox doctor
vox warmup start
vox transcribe bench /path/to/audio.wav 5
vox perf dashboard --client <integration>
```

1. `vox doctor`
2. `vox warmup start`
3. `vox transcribe bench /path/to/audio.wav 5`
4. `vox perf dashboard --client <integration>`

## Recommended client naming

Use stable product-surface IDs instead of per-user or per-session IDs:

- `vox-cli`
- `menu-bar`
- `browser-extension`
- `editor-plugin`

This keeps dashboard slices meaningful over time.

## Performance triage order

When a user reports that transcription feels slow:

1. confirm whether the report is about hot-path inference or cold-path readiness
2. inspect `inferenceMs` before speculating about model quality
3. inspect `totalMs` and `modelLoadMs` to separate warm-up cost from steady-state cost
4. compare samples by `clientId` and `route`

## Contributor checklist

- keep `clientId`, `route`, and `modelId` intact in telemetry
- avoid hiding model lifecycle inside helpers that make latency opaque
- prefer repeatable file-based benchmarks before changing live-session behavior

See [Observability](./observability.md) for metric interpretation and [Quickstart](./quickstart.md) for installation recovery.
