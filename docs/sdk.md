# SDK (Daemon Client)

> `@voxd/sdk` is for native apps and Node/Bun processes that connect directly to the daemon over a local socket. For web apps or browser extensions, use [`@voxd/client`](./web-integration.md) instead — it talks to the Vox Companion over HTTP.

`packages/client/` -- connects to the local runtime, manages models and warm-up, transcribes files, creates live sessions, and returns stage metrics with word-level timings.

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

## Configuration

```ts
const client = new VoxClient({
  clientId: "menu-bar",    // stable identity for telemetry
  port: 42137,             // override daemon port
  host: "127.0.0.1",       // override daemon host
});
```

On the daemon side, set `VOX_PORT` or `VOX_HOST` environment variables to override defaults.

## Integration advice

- use a stable `clientId` per product surface — `menu-bar`, `browser-extension`, `vox-cli`
- warm on intent, not on every keystroke
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve raw metrics in your own telemetry if the app already exports traces
