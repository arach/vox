# SDK (Companion Client)

> Apple apps on macOS and iOS can embed Vox's Swift packages directly. `@voxd/sdk` is the TypeScript client for Bun/Node tools and other companion-connected integrations that connect to `voxd` over local WebSocket JSON-RPC. For web apps or browser extensions, use [`@voxd/client`](./web-integration.md) instead — it talks to Vox Companion over HTTP.

`packages/client/` -- connects to `voxd` when you want out-of-process access to models, warm-up, transcription, synthesis, and stage metrics.

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
  listVoices(modelId?: string): Promise<unknown>;
  installModel(modelId?: string): Promise<unknown>;
  preloadModel(modelId?: string): Promise<unknown>;
  getWarmupStatus(modelId?: string): Promise<unknown>;
  startWarmup(modelId?: string): Promise<unknown>;
  scheduleWarmup(modelId?: string, delayMs?: number): Promise<unknown>;
  transcribeFile(path: string): Promise<FileTranscriptionResult>;
  synthesize(text: string, options?: SynthesisOptions): Promise<SynthesisResult>;
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

All client methods throw when `voxd` is unreachable, the model isn't installed, or a transcription or synthesis request fails. Errors are plain `Error` instances, so check `message` for a human-readable description.

```ts
try {
  const result = await client.transcribeFile("/tmp/audio.wav");
} catch (err) {
  // Common causes:
  // - Companion not running: start with `vox daemon start`
  // - Model not installed: run `vox models install` first
  // - Request failed: daemon logs have details (`vox logs daemon`)
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

- embed Swift directly for macOS and iOS apps; use `@voxd/sdk` when you want Vox Companion access from JS or tooling
- use a stable `clientId` per product surface — `menu-bar`, `browser-extension`, `vox-cli`
- warm on intent, not on every keystroke
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve raw metrics in your own telemetry if the app already exports traces
