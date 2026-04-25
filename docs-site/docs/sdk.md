# SDK

`packages/client/` -- connects to the local runtime, manages models, voices, and warm-up, transcribes files, synthesizes speech, creates live sessions, and returns stage metrics.

## Example

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const transcript = await client.transcribeFile("/tmp/sample.wav", "parakeet:v3");
const voices = await client.listVoices("avspeech:system");
const speech = await client.synthesize("Hello from Vox", {
  modelId: "avspeech:system",
  voiceId: voices[0]?.id,
  format: "wav",
});

console.log(transcript.text);
console.log(transcript.metrics?.inferenceMs);
console.log(speech.audioBytes);
console.log(speech.metrics?.synthesisMs);

client.disconnect();
```

## Client Identity

`clientId` is used to attribute latency by consumer, compare route-level behavior across integrations, and support multi-client workflows.

## Main methods

```ts
interface VoxClientSurface {
  connect(): Promise<void>;
  disconnect(): void;
  doctor(): Promise<unknown>;
  listModels(): Promise<unknown>;
  listVoices(modelId?: string): Promise<unknown>;
  installModel(modelId?: string): Promise<unknown>;
  preloadModel(modelId?: string): Promise<unknown>;
  getWarmupStatus(modelId?: string): Promise<unknown>;
  startWarmup(modelId?: string): Promise<unknown>;
  scheduleWarmup(modelId?: string, delayMs?: number): Promise<unknown>;
  transcribeFile(path: string): Promise<FileTranscriptionResult>;
  synthesize(text: string, options?: SynthesisOptions): Promise<SynthesisResult>;
  getLiveSessionStatus(): Promise<LiveSessionStatus | null>;
  cancelLiveSession(sessionId?: string): Promise<{ cancelled: boolean; sessionId: string }>;
  createLiveSession(): Promise<unknown>;
}
```

## File result shape

```ts
interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}
```

## Synthesis result shape

```ts
interface SynthesisResult {
  modelId: string;
  voiceId: string;
  format: string;
  contentType: string;
  audio: Uint8Array;
  audioBytes: number;
  elapsedMs: number;
  metrics?: SynthesisMetrics;
}
```

## Integration advice

- use a stable `clientId` per product surface such as `menu-bar`, `browser-extension`, or `vox-cli`
- warm on intent, not on every keystroke
- call `listVoices(modelId)` before pinning a TTS voice in product code
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve raw transcription and synthesis metrics in your own telemetry if the app already exports traces
