# API

Public protocol and SDK-facing type shapes.

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
- `transcribe.stopSession`
- `transcribe.cancelSession`

## Stable dimensions

Present on every performance sample. Do not drop these:

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
}
```

## Warm-up states

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

Apps use this to tell whether the runtime is cold, warming, or ready for hot-path transcription.
