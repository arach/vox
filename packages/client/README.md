# @voxd/sdk

TypeScript client for [Vox Companion](https://github.com/arach/vox) (`voxd`). Connects over local WebSocket JSON-RPC for models, warm-up, file transcription, synthesis, live sessions, history, and stage metrics.

Use this package from **Bun or Node** tools and companion-connected integrations.

| Surface | Package |
|---------|---------|
| Bun / Node companion client | **`@voxd/sdk`** (this package) |
| Browser / extension HTTP client | [`@voxd/client`](https://www.npmjs.com/package/@voxd/client) |
| Operator CLI | [`@voxd/cli`](https://www.npmjs.com/package/@voxd/cli) |
| Native Apple apps | Embed Swift packages (`VoxCore`, `VoxEngine`) directly |

## Install

```bash
npm install @voxd/sdk
# or
bun add @voxd/sdk
```

Requires **Node 22+** (or Bun) and a running Vox Companion on the machine.

```bash
# Companion not installed yet?
# https://voxd.cc/download
# or from the CLI after install:
npm install -g @voxd/cli
vox install
vox doctor
```

## Quick start

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "my-tool" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const transcript = await client.transcribeFile("/tmp/sample.wav", "parakeet:v3");
console.log(transcript.text);
console.log(transcript.metrics?.inferenceMs);
console.log(transcript.words);

const voices = await client.listVoices("avspeech:system");
const speech = await client.synthesize("Hello from Vox", {
  modelId: "avspeech:system",
  voiceId: voices[0]?.id,
  format: "wav",
});
console.log(speech.audioBytes);
console.log(speech.metrics?.synthesisMs);

client.disconnect();
```

## Configuration

```ts
const client = new VoxClient({
  clientId: "menu-bar", // stable identity for telemetry
  port: 42137,          // override companion-ws daemon port
  host: "127.0.0.1",    // override daemon host
});
```

Port discovery prefers `~/.vox/runtime.json` when present. On the daemon side:

| Variable | Default | Role |
|----------|---------|------|
| `VOX_PORT` | `42137` | Companion WebSocket (`companion-ws`) |
| `VOX_HOST` | `127.0.0.1` | Bind / connect host |
| `VOX_HOME` | `~/.vox` | Runtime data directory |

`clientId` attributes latency and session ownership across multi-client setups. Prefer stable product names (`menu-bar`, `vox-cli`, your app id).

## Main surface

```ts
interface VoxClientSurface {
  connect(): Promise<void>;
  disconnect(): void;
  connected: boolean;

  health(): Promise<Record<string, unknown>>;
  doctor(): Promise<DoctorReport>;

  listModels(): Promise<ModelInfo[]>;
  listVoices(modelId?: string): Promise<VoiceInfo[]>;
  installModel(modelId?: string, onProgress?: (e: ModelProgress) => void): Promise<ModelInfo>;
  preloadModel(modelId?: string, onProgress?: (e: ModelProgress) => void): Promise<ModelInfo>;

  getWarmupStatus(modelId?: string): Promise<WarmupStatus>;
  startWarmup(modelId?: string): Promise<WarmupStatus>;
  scheduleWarmup(modelId?: string, delayMs?: number): Promise<WarmupStatus>;

  transcribeFile(path: string, modelId?: string): Promise<FileTranscriptionResult>;
  annotateFile(path: string, options?: AnnotateOptions): Promise<FileAnnotationResult>;
  synthesize(text: string, options?: SynthesisOptions): Promise<SynthesisResult>;

  listHistory(options?: HistoryListOptions): Promise<HistoryListResult>;
  getHistoryRecord(id: string): Promise<SpeechHistoryRecord | null>;
  deleteHistoryRecord(id: string): Promise<boolean>;

  getLiveSessionStatus(): Promise<LiveSessionStatus | null>;
  stopLiveSession(sessionId?: string): Promise<StopLiveSessionResult>;
  cancelLiveSession(sessionId?: string): Promise<{ cancelled: boolean; sessionId: string }>;
  createLiveSession(): VoxLiveSession;

  // Low-level JSON-RPC
  call(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
  callStreaming(
    method: string,
    params: Record<string, unknown> | undefined,
    onProgress: (event: string, data: Record<string, unknown>) => void,
  ): Promise<Record<string, unknown>>;
}
```

### Result shapes

```ts
interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
  historyId?: string;
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

interface SynthesisOptions {
  modelId?: string;
  voiceId?: string;
  format?: string;
  speed?: number;
  instructions?: string;
  credentials?: Record<string, string>;
  speechTiming?: boolean | SpeechTiming;
}
```

Warm-up states: `"idle" | "scheduled" | "warming" | "ready" | "failed"`.

## Live sessions

```ts
const session = client.createLiveSession();

session.on("state", (e) => console.log(e.state));
session.on("partial", (e) => console.log("partial:", e.text));
session.on("final", (e) => console.log("final:", e.text));

try {
  const final = await session.start({ modelId: "parakeet:v3" });
  console.log(final.text, final.metrics?.inferenceMs);
} finally {
  await session.cancel(); // always release the mic
}
```

## Metrics

Transcription and synthesis responses include stage timings. Compare:

- **`inferenceMs` / `synthesisMs`** — hot model work
- **`totalMs`** — end-to-end wall time
- **`modelLoadMs`** — cold start (near zero after warm-up)

Samples are also written by the companion to `~/.vox/performance.jsonl` with `clientId`, `route`, and `modelId`.

## Error handling

Methods throw plain `Error` instances when the companion is unreachable, a model is missing, or a request fails.

```ts
try {
  const result = await client.transcribeFile("/tmp/audio.wav");
} catch (err) {
  // Companion down: vox daemon start / vox install
  // Model missing: vox models list && vox models install
  // Voice mismatch: client.listVoices(modelId)
  console.error(err instanceof Error ? err.message : err);
}
```

## Integration tips

- Use a stable `clientId` per product surface.
- Warm on intent (`startWarmup` / `scheduleWarmup`), not on every request.
- Call `listVoices(modelId)` before hard-coding a TTS voice.
- For browser apps, use `@voxd/client` over the HTTP bridge instead of this package.
- For Apple apps, embed the Swift packages rather than talking to `voxd` in-process.

## Docs

- [SDK guide](https://github.com/arach/vox/blob/main/docs/sdk.md)
- [Runtime](https://github.com/arach/vox/blob/main/docs/runtime.md)
- [API](https://github.com/arach/vox/blob/main/docs/api.md)
- [Quickstart](https://github.com/arach/vox/blob/main/docs/quickstart.md)

## License

MIT
