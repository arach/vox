# Observability Facts

- primary operator commands:
  - `vox transcribe file --metrics /path/to/audio.wav`
  - `vox transcribe bench /path/to/audio.wav 5`
  - `vox speak --no-play --output /tmp/out.wav "hello world"`
  - `vox speak bench "hello world" 5`
  - `vox perf dashboard`
- inference speed should be evaluated from `inferenceMs` / `synthesisMs`, not `totalMs`
- total latency should be evaluated from `totalMs`
- exported dimensions:
  - `clientId`
  - `route`
  - `modelId`
  - `voiceId` for synthesis
