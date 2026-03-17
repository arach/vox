# Runtime Audit Prompt

Use this when auditing Vox runtime behavior.

## Goal

Determine whether a latency or correctness issue belongs to:

- daemon lifecycle
- model warm-up
- audio preparation
- inference
- SDK parsing
- CLI operator flow

## Checklist

1. Run `vox doctor`
2. Inspect `vox warmup status`
3. Run `vox transcribe file --metrics /path/to/audio.wav`
4. Run `vox transcribe bench /path/to/audio.wav 5`
5. Run `vox perf dashboard --client <clientId>`
6. Compare `totalMs` vs `inferenceMs`
7. Confirm whether the issue is warm-path or cold-path only
