# Observability

Vox treats transcription telemetry as a first-class runtime feature.

## Dimensions

Each performance sample is tagged with:

- `clientId`
- `route`
- `modelId`

## Metrics

Current metrics include:

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Additional useful derived values:

- `realtimeFactor`
- warm vs cold path behavior from `modelLoadMs`
- effective audio-to-text speed from `audioDurationMs / inferenceMs`

## Storage

The runtime appends JSON lines to:

```text
~/.vox/performance.jsonl
```

That local store powers the CLI dashboard today and can later be exported to another metrics backend if needed.

## Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

## Philosophy

Loaded-model inference speed and end-to-end latency are different things.

Vox records both:

- `inferenceMs` tells you how fast the hot model is.
- `totalMs` tells you what the user actually experienced.

## Example sample

```json
{
  "clientId": "raycast",
  "route": "transcribe.file",
  "modelId": "parakeet:v3",
  "audioDurationMs": 5110,
  "inferenceMs": 151,
  "totalMs": 165
}
```

## How to read the dashboard

- Compare clients against each other only when the audio shape is similar
- Use `inferenceMs` to judge loaded-model speed
- Use `totalMs` to judge end-user experience
- Treat large `modelLoadMs` spikes as warm-up lifecycle events, not steady-state inference regressions
