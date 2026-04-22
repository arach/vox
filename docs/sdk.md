# SDK (Daemon Client)

> **Two clients, two use cases.** This is `@voxd/sdk` — the TypeScript SDK for native apps and Node/Bun processes that connect directly to the Vox daemon over a local socket. If you're building a web app or browser extension, use [`@voxd/web`](./web-integration.md) instead, which talks to the Vox Companion over HTTP.

The TypeScript SDK lives in `packages/client/`.

## Main Capabilities

- connect to the local runtime
- inspect health and doctor checks
- list/install/preload models
- start and schedule warm-up
- transcribe files
- create live sessions
- receive stage metrics and word-level timings on transcription results

## Example

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const result = await client.transcribeFile("/tmp/sample.wav");

console.log(result.text);
console.log(result.metrics?.inferenceMs);
console.log(result.words);

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
  words: WordTiming[];
}
```

## Error handling

All client methods throw when the daemon is unreachable, the model isn't installed, or a transcription fails. Errors are plain `Error` instances — check `message` for a human-readable description.

```ts
try {
  const result = await client.transcribeFile("/tmp/audio.wav");
} catch (err) {
  // Common causes:
  // - Daemon not running: start with `vox daemon start`
  // - Model not installed: run `vox models install` first
  // - Transcription failed: daemon logs have details (`vox logs daemon`)
  console.error(err.message);
}
```

For live sessions, call `session.cancel()` in a `finally` block to ensure the microphone is always released:

```ts
const session = await client.createLiveSession();
try {
  // ...use session
} finally {
  await session.cancel();
}
```

## Integration advice

- use a stable `clientId` per product surface such as `menu-bar`, `browser-extension`, or `vox-cli`
- warm on intent, not on every keystroke
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve the raw metrics in your own telemetry if the app already exports traces
