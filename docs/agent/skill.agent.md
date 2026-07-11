# Operations Facts

- start with `vox doctor`
- distinguish cold readiness from hot inference before changing code
- warm explicitly with `vox warmup start [modelId]`
- benchmark ASR with `vox transcribe bench <path> [runs]`
- benchmark TTS with `vox speak bench <text> [runs]`
- inspect tagged samples with `vox perf dashboard`
- keep client IDs stable by product surface, not user or session
- read `inferenceMs` or `synthesisMs` separately from `totalMs`
- use file-based benchmarks before changing live-session behavior
