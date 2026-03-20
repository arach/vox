# SDK

The TypeScript SDK lives in `packages/client/`.

## Main Capabilities

- connect to the local runtime
- inspect health and doctor checks
- list/install/preload models
- start and schedule warm-up
- transcribe files
- create live sessions
- receive stage metrics on transcription results

## Example

```ts
import { VoxClient } from "@vox/client";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const result = await client.transcribeFile("/tmp/sample.wav");

console.log(result.text);
console.log(result.metrics?.inferenceMs);

client.disconnect();
```

## Client Identity

`clientId` matters.

It is used by the runtime to:

- attribute latency by consumer
- inspect route-level behavior across integrations
- support multi-client operator workflows

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
