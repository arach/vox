# Web Integration (Companion Client)

> For Apple apps, embed Vox's Swift packages directly. For Bun/Node companion clients, use [`@voxd/sdk`](./sdk.md) instead — it connects to `voxd` over local WebSocket JSON-RPC.

`@voxd/client` adds local transcription to web apps and browser extensions. Talks to the Vox Companion on the user's Mac over a local HTTP bridge. No server needed.

This browser client is STT / alignment focused today. For TTS, use the companion-facing TypeScript SDK or the CLI.

## Install

```bash
npm install @voxd/client
```

## Quick start

```ts
import { createVoxdClient } from "@voxd/client";

const client = createVoxdClient();

// Check if the companion is running
if (await client.probe()) {
  // Transcribe audio from a blob
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

Call `probe()` on page load. It hits the companion's health endpoint with a short timeout and returns `true` or `false`. Fails silently when the companion is not installed.

```ts
const client = createVoxdClient();
const available = await client.probe();
```

After probing, check `client.state` for the current connection state: `"connected"`, `"unavailable"`, `"probing"`, or `"unknown"`.

## Capabilities

Once connected, check what the companion supports:

```ts
const caps = await client.capabilities();

if (caps.features.alignment) {
  // Word-level timestamps available
}

if (caps.features.local_asr) {
  // Local transcription available
}
```

## Transcription

### From a Blob or File

Use `transcribe()` when you have audio data in the browser (recording, TTS clip, file upload).

```ts
const result = await client.transcribe({
  audio: blob,          // Blob, File, or ArrayBuffer
  language: "en",
  timestamps: true,     // include word-level timing
});

result.text;            // full transcript
result.words;           // [{ word, start, end }, ...]
result.durationMs;      // audio duration
```

### From a URL

Use `align()` when the audio lives on a server. The companion fetches it directly, avoiding a round trip through the browser.

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

alignment.words;       // [{ word, start, end }, ...]
alignment.durationMs;
```

`align()` creates a job, polls until done, and returns the result. Blocks up to 5 minutes.

### Lower-level job API

For more control, use `createJob()` and `getJob()` directly:

```ts
const { jobId } = await client.createJob({
  type: "alignment",
  source: { audioUrl: "https://your-app.com/audio/abc.mp3" },
  metadata: { cacheKey: "abc123" },
});

// Poll manually
const status = await client.getJob(jobId);
// status.status: "accepted" | "processing" | "completed" | "failed"
// status.result?.alignment: { words, durationMs }
```

## Graceful degradation

Vox Companion is a first-class deployment mode, but it will not be installed or running on every machine. Build your app to probe for it and degrade gracefully when it is unavailable.

```ts
const client = createVoxdClient();

async function getAlignment(audioUrl: string) {
  // Try local companion first
  if (await client.probe()) {
    try {
      return await client.align({ source: { audioUrl } });
    } catch {
      // Fall through to cloud
    }
  }

  // Fallback to cloud API or heuristic timing
  return await cloudAlignmentFallback(audioUrl);
}
```

## When the companion isn't installed

If `probe()` returns false, you can prompt the user to install:

```ts
if (!await client.probe()) {
  // Show install prompt in your UI
  // Link to: https://github.com/arach/vox/releases/latest/download/Vox.dmg
}
```

Or try launching it via deep link (works if installed but not running):

```ts
client.launch(); // triggers vox://launch
```

## Error handling

All methods throw `VoxDError` with a `code` property:

```ts
import { VoxDError } from "@voxd/client";

try {
  const result = await client.transcribe({ audio: blob });
} catch (err) {
  if (err instanceof VoxDError) {
    switch (err.code) {
      case "network_error":  // companion unreachable
      case "http_error":     // non-2xx response
      case "job_failed":     // transcription failed
      case "timeout":        // job took too long
      case "no_result":      // job completed without result
    }
  }
}
```

## HTTP bridge reference

The companion listens on `http://127.0.0.1:43115` by default (configurable via `host` and `port` options). These endpoints are what `@voxd/client` calls under the hood.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | Open | Liveness check |
| `GET` | `/capabilities` | Origin | Features, backends, models |
| `POST` | `/jobs` | Origin | Create alignment/transcription job |
| `GET` | `/jobs/:id` | Origin | Poll job status |
| `POST` | `/transcribe` | Origin | Upload audio for transcription |
| `GET` | `/live` | Origin | Live session status |
| `POST` | `/live` | Origin | Start a live recording session (streaming NDJSON) |
| `POST` | `/live/stop` | Origin | Stop a live session and get final transcript |
| `POST` | `/live/cancel` | Origin | Cancel a live session without transcribing |

**Origin gating:** All endpoints except `/health` require a valid `Origin` header. Vox ships with built-in origins for first-party apps. Add your own in Vox settings, or drop a JSON file into `~/.vox/origins.d/`:

```json
{"origins":["https://app.example.com"]}
```

Vox merges all origin sources. Wildcard ports work on loopback hosts (`http://localhost:*`).

## Configuration

```ts
const client = createVoxdClient({
  host: "127.0.0.1",   // default — override for non-loopback setups
  port: 43115,          // default
  baseUrl: "http://...",// overrides host + port when set
  clientId: "my-app",   // stable identity for telemetry
  probeTimeout: 2000,   // ms before probe gives up
  pollInterval: 500,    // ms between job status polls
});
```

On the daemon side, set `VOX_PORT`, `VOX_BRIDGE_PORT`, or `VOX_HOST` environment variables to override defaults.
