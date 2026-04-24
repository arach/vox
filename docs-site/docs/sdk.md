# SDK

`packages/client/` -- connects to the local runtime, manages models and warm-up, transcribes files, creates live sessions, and returns stage metrics.

## Example

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const result = await client.transcribeFile("/tmp/sample.wav");

console.log(result.text);
console.log(result.metrics?.inferenceMs);

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
  installModel(modelId?: string): Promise<unknown>;
  preloadModel(modelId?: string): Promise<unknown>;
  getWarmupStatus(modelId?: string): Promise<unknown>;
  startWarmup(modelId?: string): Promise<unknown>;
  scheduleWarmup(modelId?: string, delayMs?: number): Promise<unknown>;
  transcribeFile(path: string): Promise<FileTranscriptionResult>;
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
}
```

## Integration advice

- use a stable `clientId` per product surface such as `menu-bar`, `browser-extension`, or `vox-cli`
- warm on intent, not on every keystroke
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve the raw metrics in your own telemetry if the app already exports traces
