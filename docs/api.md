---
title: API
description: Current companion RPC routes, TypeScript SDK entrypoints, result types, and performance shapes.
---

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
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`

### Annotation

- `annotate.file`

### Synthesis

- `synthesize.voices`
- `synthesize.generate`
- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`

## Performance samples

These fields are present on every performance sample recorded to `~/.vox/performance.jsonl`.

```ts
type PerformanceRoute =
  | "annotate.file"
  | "transcribe.file"
  | "transcribe.live"
  | "synthesize.generate"
  | "synthesize.startSession"
  | string;
```

```ts
interface PerformanceSample {
  timestamp: string;
  clientId: string;
  route: PerformanceRoute;
  modelId: string;
  voiceId?: string;
  outcome: "ok" | "error" | "cancelled" | string;
  textLength: number;
  error?: string;
  metrics?: PerformanceMetrics;
}

interface PerformanceMetrics {
  traceId: string;
  audioDurationMs: number;
  wasPreloaded: boolean;
  modelCheckMs: number;
  modelLoadMs: number;
  inferenceMs: number;
  totalMs: number;
  inputBytes?: number;
  fileCheckMs?: number;
  audioLoadMs?: number;
  audioPrepareMs?: number;
  characterCount?: number;
  outputBytes?: number;
  voiceResolveMs?: number;
  synthesisMs?: number;
  realtimeFactor?: number;
}
```

Current emitted performance routes:

- `transcribe.file`
- `annotate.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

## Core TypeScript SDK Entry Points

### `VoxClient`

- `connect()`
- `disconnect()`
- `doctor()`
- `listModels()`
- `listVoices()`
- `installModel()`
- `preloadModel()`
- `getWarmupStatus()`
- `startWarmup()`
- `scheduleWarmup()`
- `transcribeFile()`
- `annotateFile()`
- `synthesize()`
- `getLiveSessionStatus()`
- `cancelLiveSession()`
- `createLiveSession()`

### `FileTranscriptionResult`

- `modelId`
- `text`
- `elapsedMs`
- `metrics`
- `words`

### `SynthesisResult`

- `modelId`
- `voiceId`
- `format`
- `contentType`
- `audio`
- `audioBytes`
- `elapsedMs`
- `metrics`

### `FileAnnotationResult`

- `modelId`
- `text`
- `elapsedMs`
- `metrics`
- `words`
- `speakers`

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

### `SynthesisMetrics`

- `traceId`
- `characterCount`
- `audioDurationMs`
- `outputBytes`
- `wasPreloaded`
- `modelCheckMs`
- `modelLoadMs`
- `voiceResolveMs`
- `synthesisMs`
- `inferenceMs`
- `totalMs`
- `realtimeFactor`

### `AnnotationMetrics`

- `traceId`
- `audioDurationMs`
- `inputBytes`
- `wasPreloaded`
- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `diarizationMs`
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

interface SpeakerSegment {
  speakerId: string;
  start: number;
  end: number;
  confidence?: number | null;
}

interface AttributedWordTiming {
  word: string;
  start: number;
  end: number;
  confidence: number;
  speakerId?: string | null;
}

interface AnnotationMetrics {
  traceId: string;
  audioDurationMs: number;
  inputBytes: number;
  wasPreloaded: boolean;
  fileCheckMs: number;
  modelCheckMs: number;
  modelLoadMs: number;
  audioLoadMs: number;
  audioPrepareMs: number;
  diarizationMs: number;
  totalMs: number;
  realtimeFactor: number;
}

interface FileAnnotationResult {
  modelId: string;
  text?: string;
  elapsedMs: number;
  metrics?: AnnotationMetrics;
  words: AttributedWordTiming[];
  speakers: SpeakerSegment[];
}

interface SynthesisOptions {
  modelId?: string;
  voiceId?: string;
  format?: string;
  speed?: number;
  instructions?: string;
  speechTiming?: boolean | SpeechTimingRequest;
  credentials?: {
    OPENAI_API_KEY?: string;
    openaiApiKey?: string;
    openai_api_key?: string;
  };
}

interface SpeechTimingRequest {
  enabled?: boolean;
  modelId?: string;
  cues?: Array<{
    id: string;
    text?: string;
    textStart?: number;
    textEnd?: number;
  }>;
}

interface SynthesisMetrics {
  traceId: string;
  characterCount: number;
  audioDurationMs: number;
  outputBytes: number;
  wasPreloaded: boolean;
  modelCheckMs: number;
  modelLoadMs: number;
  voiceResolveMs: number;
  synthesisMs: number;
  inferenceMs: number;
  totalMs: number;
  realtimeFactor: number;
}

interface SynthesisResult {
  modelId: string;
  voiceId: string;
  format: string;
  contentType: string;
  audio: Uint8Array;
  audioBytes: number;
  elapsedMs: number;
  metrics?: SynthesisMetrics;
  speechTiming?: SpeechTiming;
}

interface SpeechTiming {
  source: "asr" | "native" | "estimated" | string;
  modelId: string;
  elapsedMs: number;
  words: SpeechTimingWord[];
  cues: SpeechTimingCue[];
}
```

## Warm-up states

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

Apps use this to tell whether the runtime is cold, warming, or ready for hot-path speech.

See the [SDK Guide](./sdk.md) for usage patterns and [Runtime](./runtime.md) for route ownership and session semantics.
