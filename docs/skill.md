# Vox Skill Notes

When building with Vox, the highest-value workflows are:

- add warm-up before first speech
- preserve `clientId` in SDK initialization
- benchmark warm performance with real audio
- read the local dashboard before speculating about latency

Recommended operator loop:

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
