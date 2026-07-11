---
title: Observability
description: Read Vox performance samples, stage timings, client dimensions, and operator dashboards.
---

Telemetry is built into the runtime for both transcription and synthesis. Each performance sample includes:

- `clientId`
- `route`
- `modelId`
- `voiceId` for synthesis routes when a voice is selected
- `outcome`
- nested `metrics`

## Metrics

Transcription metrics:

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Synthesis metrics:

- `modelCheckMs`
- `modelLoadMs`
- `voiceResolveMs`
- `synthesisMs`
- `totalMs`
- `audioDurationMs`
- `outputBytes`
- `characterCount`

Derived values: `realtimeFactor`, warm vs cold from `modelLoadMs`, audio-to-text speed from `audioDurationMs / inferenceMs`, and text-to-audio speed from `audioDurationMs / synthesisMs`.

## Storage

The runtime appends JSON lines to:

```text
~/.vox/performance.jsonl
```

The CLI dashboard reads from this file. You can also export it to another metrics backend.

Current emitted performance routes:

- `transcribe.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

Cancelled synthesis sessions are recorded under `synthesize.startSession` with `outcome: "cancelled"`.

## Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox speak --metrics "hello world"
vox speak bench "hello world" 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

## Reading the numbers

`inferenceMs`, `synthesisMs`, and `totalMs` measure different things.

- For ASR, `inferenceMs` is how fast the hot model ran.
- For TTS, `synthesisMs` is how long audio generation took once the request was inside the model.
- `totalMs` is what the user experienced end-to-end.

## Example sample

```json
{
  "timestamp": "2026-04-25T17:54:26Z",
  "clientId": "menu-bar",
  "route": "synthesize.generate",
  "modelId": "avspeech:system",
  "voiceId": "com.apple.voice.compact.en-US.Samantha",
  "outcome": "ok",
  "textLength": 14,
  "metrics": {
    "audioDurationMs": 1240,
    "synthesisMs": 182,
    "inferenceMs": 182,
    "totalMs": 196
  }
}
```

## Dashboard tips

- Only compare clients when the prompt or audio shape is similar.
- Use `inferenceMs` for loaded-model ASR speed.
- Use `synthesisMs` for loaded-model TTS speed.
- Use `totalMs` for end-user latency.
- Large `modelLoadMs` spikes are warm-up events, not inference regressions.

See [Runtime](./runtime.md) for emitted routes and [API](./api.md) for the current performance sample shape.
