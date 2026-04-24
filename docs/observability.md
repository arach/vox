# Observability

Telemetry is built into the runtime. Each performance sample is tagged with:

- `clientId`
- `route`
- `modelId`

## Metrics

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Derived values: `realtimeFactor`, warm vs cold from `modelLoadMs`, audio-to-text speed from `audioDurationMs / inferenceMs`.

## Storage

The runtime appends JSON lines to:

```text
~/.vox/performance.jsonl
```

The CLI dashboard reads from this file. You can also export it to another metrics backend.

## Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

## Reading the numbers

`inferenceMs` and `totalMs` measure different things. `inferenceMs` is how fast the hot model ran. `totalMs` is what the user experienced end-to-end.

## Example sample

```json
{
  "clientId": "menu-bar",
  "route": "transcribe.file",
  "modelId": "parakeet:v3",
  "audioDurationMs": 5110,
  "inferenceMs": 151,
  "totalMs": 165
}
```

## Dashboard tips

- Only compare clients when the audio is similar.
- Use `inferenceMs` for loaded-model speed.
- Use `totalMs` for end-user latency.
- Large `modelLoadMs` spikes are warm-up events, not inference regressions.
