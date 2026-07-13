# @voxd/client

Browser client for [Vox Companion](https://github.com/arach/vox). Talks to the local HTTP bridge on the user's Mac for transcription, alignment, live sessions, and companion discovery. No remote server required.

This package is **STT / alignment focused**. For TTS from Node or Bun tooling, use [`@voxd/sdk`](https://www.npmjs.com/package/@voxd/sdk) or the [`@voxd/cli`](https://www.npmjs.com/package/@voxd/cli).

| Surface | Package |
|---------|---------|
| Browser / extension HTTP client | **`@voxd/client`** (this package) |
| Bun / Node companion client | [`@voxd/sdk`](https://www.npmjs.com/package/@voxd/sdk) |
| Operator CLI | [`@voxd/cli`](https://www.npmjs.com/package/@voxd/cli) |
| Native Apple apps | Embed Swift packages (`VoxCore`, `VoxEngine`) directly |

## Install

```bash
npm install @voxd/client
# or
bun add @voxd/client
```

The user needs Vox Companion installed and running on the machine:

- Download: [voxd.cc/download](https://voxd.cc/download)
- Or install the CLI and LaunchAgent: `npm install -g @voxd/cli && vox install`

## Quick start

```ts
import { createVoxdClient } from "@voxd/client";

const client = createVoxdClient({ clientId: "my-web-app" });

if (await client.probe()) {
  const result = await client.transcribe({
    audio: audioBlob,
    language: "en",
    timestamps: true,
  });

  console.log(result.text);
  console.log(result.words); // word-level timestamps
}
```

## Discovery

Call `probe()` on page load. It hits the companion health endpoint with a short timeout and returns `true` or `false`. Safe when Companion is not installed.

```ts
const available = await client.probe();
// client.state: "connected" | "unavailable" | "probing" | "unknown"
// client.isConnected === true when connected
```

Once connected:

```ts
const caps = await client.capabilities();

if (caps.features.local_asr) {
  // local transcription available
}
if (caps.features.alignment) {
  // word-level timestamps available
}
```

If Companion is installed but not running:

```ts
client.launch();       // vox://launch
client.openSettings(); // vox://settings
```

## Transcription

### From a Blob, File, or ArrayBuffer

```ts
const result = await client.transcribe({
  audio: blob,       // Blob | File | ArrayBuffer
  language: "en",
  timestamps: true,  // include word-level timing
  // modelId?: string
  // format?: string
  // metadata?: Record<string, unknown>
});

result.text;
result.words;      // [{ word, start, end }, ...]
result.durationMs;
```

This client does **not** own microphone capture. Use `getUserMedia` (or your own recorder), then pass the resulting blob.

### From a URL (alignment)

When audio lives on a server, the companion can fetch it directly:

```ts
const alignment = await client.align({
  source: {
    audioUrl: "https://your-app.com/api/audio/abc123",
    format: "mp3",
  },
  metadata: {
    documentId: "doc_123",
    pageNumber: 2,
  },
});

alignment.words;
alignment.durationMs;
```

`align()` creates a job, polls until done, and returns the result (up to ~5 minutes).

### Lower-level jobs

```ts
const { jobId } = await client.createJob({
  type: "alignment",
  source: { audioUrl: "https://your-app.com/audio/abc.mp3" },
  metadata: { cacheKey: "abc123" },
});

const status = await client.getJob(jobId);
// status.status: "accepted" | "processing" | "completed" | "failed"
// status.result?.alignment: { words, durationMs }
```

## Live sessions

```ts
const session = client.createLiveSession();

session.on("state", (e) => console.log(e.state));
session.on("partial", (e) => console.log(e.text));
session.on("final", (e) => console.log(e.text));

try {
  const final = await session.start({ modelId: "parakeet:v3" });
  console.log(final.text);
} finally {
  await session.cancel();
}
```

Also available: `getLiveSessionStatus()`, `stopLiveSession()`, `cancelLiveSession()`.

## Voice FX (`@voxd/client/fx`)

Optional Web Audio helpers for radio / walkie / dispatcher-style playback. Framework-agnostic; depends only on `AudioContext` and `fetch`.

```ts
import {
  decodeAudioFromUrl,
  playWithVoiceFx,
  VOICE_FX_PRESETS,
} from "@voxd/client/fx";

const buffer = await decodeAudioFromUrl(audioUrl);
const preset = VOICE_FX_PRESETS.find((p) => p.id === "pocket-walkie");
const handle = playWithVoiceFx(buffer, { params: preset?.params });
await handle.promise;
```

## Configuration

```ts
const client = createVoxdClient({
  host: "127.0.0.1",    // default
  port: 43115,          // companion-http bridge port
  baseUrl: "http://...",// overrides host + port when set
  clientId: "my-app",   // stable identity for telemetry
  probeTimeout: 2000,   // ms before probe gives up
  pollInterval: 500,    // ms between job status polls
});
```

Daemon-side overrides:

| Variable | Default | Role |
|----------|---------|------|
| `VOX_BRIDGE_PORT` | `43115` | Companion HTTP bridge (`companion-http`) |
| `VOX_PORT` | `42137` | Underlying WebSocket daemon (`companion-ws`) |
| `VOX_HOST` | `127.0.0.1` | Bind host |

## Origin gating

All bridge endpoints except `/health` require a valid `Origin` header. Vox ships first-party origins; add yours in Vox settings or:

```json
// ~/.vox/origins.d/my-app.json
{ "origins": ["https://app.example.com"] }
```

Wildcard ports work on loopback (`http://localhost:*`).

## Error handling

Methods throw `VoxDError` with a `code`:

```ts
import { createVoxdClient, VoxDError } from "@voxd/client";

try {
  const result = await client.transcribe({ audio: blob });
} catch (err) {
  if (err instanceof VoxDError) {
    switch (err.code) {
      case "network_error": // companion unreachable
      case "http_error":    // non-2xx response
      case "job_failed":    // transcription / alignment failed
      case "timeout":       // job took too long
      case "no_result":     // completed without a result
      case "live_session_error":
      case "session_cancelled":
      case "protocol_error":
    }
  }
}
```

## Graceful degradation

Companion will not be on every machine. Probe and keep a fallback:

```ts
const client = createVoxdClient();

async function getAlignment(audioUrl: string) {
  if (await client.probe()) {
    try {
      return await client.align({ source: { audioUrl } });
    } catch {
      // fall through
    }
  }
  return cloudAlignmentFallback(audioUrl);
}
```

## HTTP bridge reference

Default base: `http://127.0.0.1:43115`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | Open | Liveness |
| `GET` | `/capabilities` | Origin | Features, backends, models |
| `POST` | `/jobs` | Origin | Create alignment / transcription job |
| `GET` | `/jobs/:id` | Origin | Poll job status |
| `POST` | `/transcribe` | Origin | Upload audio for transcription |
| `GET` | `/live` | Origin | Live session status |
| `POST` | `/live` | Origin | Start live session (streaming NDJSON) |
| `POST` | `/live/stop` | Origin | Stop and finalize |
| `POST` | `/live/cancel` | Origin | Cancel without transcript |

## Docs

- [Web integration guide](https://github.com/arach/vox/blob/main/docs/web-integration.md)
- [Runtime](https://github.com/arach/vox/blob/main/docs/runtime.md)
- [API](https://github.com/arach/vox/blob/main/docs/api.md)

## License

MIT
