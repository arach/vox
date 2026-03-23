# API

This page describes the public protocol and SDK-facing shapes that other apps should rely on.

## RPC Methods

### Health and Runtime

- `health`
- `doctor.run`

### Models

- `models.list`
- `models.install`
- `models.preload`

### Warm-Up

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

### Transcription

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`

## Stable dimensions

These values should remain available anywhere the runtime records or returns performance information:

```ts
type VoxRoute =
  | "transcribe.file"
  | "transcribe.startSession"
  | "transcribe.stopSession"
  | "transcribe.cancelSession"
  | "warmup.status"
  | "warmup.start"
  | "warmup.schedule";
```

```ts
interface PerformanceSample {
  clientId: string;
  route: VoxRoute | string;
  modelId: string;
  audioDurationMs?: number;
  inferenceMs?: number;
  totalMs?: number;
}
```

## Core TypeScript SDK Entry Points

### `VoxClient`

- `connect()`
- `disconnect()`
- `doctor()`
- `listModels()`
- `installModel()`
- `preloadModel()`
- `getWarmupStatus()`
- `startWarmup()`
- `scheduleWarmup()`
- `transcribeFile()`
- `createLiveSession()`

### `FileTranscriptionResult`

- `modelId`
- `text`
- `elapsedMs`
- `metrics`
- `words`

### `TranscriptionMetrics`

- `traceId`
- `audioDurationMs`
- `inputBytes`
- `wasPreloaded`
- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `realtimeFactor`

## Interface shapes

```ts
interface TranscriptionMetrics {
  traceId: string;
  audioDurationMs?: number;
  inputBytes?: number;
  wasPreloaded?: boolean;
  fileCheckMs?: number;
  modelCheckMs?: number;
  modelLoadMs?: number;
  audioLoadMs?: number;
  audioPrepareMs?: number;
  inferenceMs?: number;
  totalMs?: number;
  realtimeFactor?: number;
}

interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}
```

## Warm-up response expectations

Warm-up APIs should make these states observable:

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

That state is useful to apps because it lets them distinguish:

- a runtime that has not been asked to warm
- a runtime that is actively warming
- a runtime that is ready for hot-path transcription
