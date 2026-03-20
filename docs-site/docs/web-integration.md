# Web Integration

Use `@voxd/client` to add local transcription to any web app. The client talks to the Vox Companion running on the user's Mac — no server needed.

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

Call `probe()` on page load. It hits `127.0.0.1:43115/health` with a short timeout and returns `true` or `false`. Safe to call unconditionally — it fails silently when the companion isn't installed.

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

Use `transcribe()` when you have audio data in the browser — from a recording, a generated TTS clip, or a file upload.

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

Use `align()` when the audio lives on a server and you want the companion to fetch it directly. This avoids moving audio through the browser twice.

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

`align()` creates a job, polls for completion, and returns the result. It blocks until the job finishes (up to 5 minutes).

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

The companion is optional. Your app should work without it.

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

The companion listens on `http://127.0.0.1:43115`. These endpoints are what `@voxd/client` calls under the hood.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | Open | Liveness check |
| `GET` | `/capabilities` | Origin | Features, backends, models |
| `POST` | `/jobs` | Origin | Create alignment/transcription job |
| `GET` | `/jobs/:id` | Origin | Poll job status |
| `POST` | `/transcribe` | Origin | Upload audio for transcription |

**Origin gating:** All endpoints except `/health` require the request `Origin` header to be in the companion's allowlist. Default: `https://uselinea.com`. Users can add origins in the Vox settings app.

## Configuration

```ts
const client = createVoxdClient({
  port: 43115,          // default
  baseUrl: "http://127.0.0.1:43115", // or use this instead of port
  probeTimeout: 2000,   // ms before probe gives up
  pollInterval: 500,    // ms between job status polls
});
```
