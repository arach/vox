---
title: Provider Protocol
description: How external transcription engines plug into Vox via JSON-RPC over stdin/stdout.
order: 35
---

# Provider Protocol

Vox separates the runtime (mic capture, sessions, routing, telemetry) from the transcription engine. Engines are called _providers_ -- external processes that speak JSON-RPC over stdin/stdout.

Parakeet is the built-in provider. You can add others: Whisper, Deepgram, a custom model, or anything that accepts audio and returns text.

## Provider Config

Providers are registered in `~/.vox/providers.json`:

```json
{
  "providers": [
    { "id": "parakeet", "builtin": true },
    {
      "id": "whisper",
      "command": ["python3", "whisper-provider.py"],
      "models": ["whisper:tiny", "whisper:base", "whisper:large"]
    }
  ]
}
```

| Field      | Type       | Required | Description                                                        |
|------------|------------|----------|--------------------------------------------------------------------|
| `id`       | `string`   | Yes      | Unique identifier for this provider.                               |
| `builtin`  | `boolean`  | No       | If `true`, Vox uses its bundled implementation. Only for Parakeet.  |
| `command`  | `string[]` | No       | The executable and arguments Vox will spawn.                       |
| `models`   | `string[]` | No       | Declares which model IDs this provider serves.                     |

## Protocol Methods

All communication uses newline-delimited JSON-RPC 2.0 over stdin (requests from Vox) and stdout (responses from the provider).

### `models`

List available models.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 1, "method": "models" }
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "models": [
      {
        "id": "whisper:large",
        "name": "Whisper Large",
        "backend": "whisper",
        "installed": true,
        "preloaded": false,
        "available": true
      }
    ]
  }
}
```

### `install`

Download or prepare model files.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 2, "method": "install", "params": { "modelId": "whisper:large" } }
```

The provider can emit progress notifications on stdout during installation:

```json
{ "jsonrpc": "2.0", "method": "notification", "params": { "event": "progress", "data": { "modelId": "whisper:large", "progress": 0.5, "status": "downloading" } } }
```

**Response:** a model info object matching the shape returned by `models`.

### `preload`

Load a model into memory so subsequent transcriptions start faster.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 3, "method": "preload", "params": { "modelId": "whisper:large" } }
```

**Response:** a model info object with `preloaded: true`.

### `transcribe`

Transcribe an audio file.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 4, "method": "transcribe", "params": { "modelId": "whisper:large", "path": "/tmp/audio.wav" } }
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "modelId": "whisper:large",
    "text": "Hello world",
    "elapsedMs": 142,
    "metrics": {
      "inferenceMs": 130,
      "modelLoadMs": 0,
      "audioLoadMs": 5,
      "audioPrepareMs": 2,
      "fileCheckMs": 1,
      "modelCheckMs": 1,
      "totalMs": 142
    }
  }
}
```

## Metrics Contract

Providers must return stage timings in the `metrics` object of every `transcribe` response. These feed into Vox telemetry tagged with `modelId`, so operators can compare providers side by side.

**Required fields:**

| Field          | Type     | Description                              |
|----------------|----------|------------------------------------------|
| `inferenceMs`  | `number` | Time spent running the model.            |
| `totalMs`      | `number` | Wall-clock time for the entire request.  |

**Optional but recommended:**

| Field            | Type     | Description                                       |
|------------------|----------|---------------------------------------------------|
| `modelLoadMs`    | `number` | Time loading the model (0 if already preloaded).   |
| `audioLoadMs`    | `number` | Time reading the audio file from disk.             |
| `audioPrepareMs` | `number` | Time resampling or converting the audio.           |
| `fileCheckMs`    | `number` | Time validating the audio file exists and is readable. |
| `modelCheckMs`   | `number` | Time checking the model is installed and ready.    |

## What Vox handles

Providers only deal with models and transcription. The runtime handles everything else:

- Mic permissions and capture -- audio arrives as a WAV file path
- Audio format normalization -- consistent sample rates and formats
- Session lifecycle -- start, stop, cancel coordinated by the daemon
- Warm-up scheduling and state
- Client identity routing (`clientId`)
- Performance telemetry collection
- Multi-client serialization -- providers see one request at a time

## Writing a provider

A provider is any executable that reads newline-delimited JSON-RPC from stdin and writes responses to stdout. Minimal TypeScript example:

```typescript
// minimal-provider.ts
import { createInterface } from "readline";

const rl = createInterface({ input: process.stdin });

for await (const line of rl) {
  const req = JSON.parse(line);

  if (req.method === "models") {
    respond(req.id, {
      models: [
        {
          id: "my-model:v1",
          name: "My Model",
          backend: "custom",
          installed: true,
          preloaded: false,
          available: true,
        },
      ],
    });
  }

  if (req.method === "transcribe") {
    const text = await myTranscribe(req.params.path);
    respond(req.id, {
      modelId: req.params.modelId,
      text,
      elapsedMs: 100,
      metrics: { inferenceMs: 95, totalMs: 100 },
    });
  }
}

function respond(id: number, result: unknown) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}
```

Register it in `~/.vox/providers.json`:

```json
{
  "providers": [
    { "id": "parakeet", "builtin": true },
    {
      "id": "my-provider",
      "command": ["bun", "run", "minimal-provider.ts"],
      "models": ["my-model:v1"]
    }
  ]
}
```

Then select it via CLI or SDK by specifying `my-model:v1` as the model.

## Provider lifecycle

Vox spawns the provider process on first use. It stays alive for the daemon's lifetime. If it crashes, Vox restarts it on the next request.

Providers should be stateless between requests. The provider process can keep model weights in memory, but Vox assumes nothing about that state -- a crash and restart must not break anything.
