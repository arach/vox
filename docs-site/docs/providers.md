---
title: Provider Protocol
description: How external STT and TTS engines plug into Vox via JSON-RPC over stdin/stdout.
order: 35
---

# Provider Protocol

Vox separates the runtime (mic capture, sessions, routing, telemetry, playback handoff) from the speech engine. Engines are called _providers_ -- external processes or built-in bridges that speak JSON-RPC over stdin/stdout.

Providers can serve either:

- ASR / STT -- accept audio and return text
- TTS -- accept text and return audio

Built-in providers include:

- `parakeet` for ASR
- `avspeech` for system TTS
- `openai-tts` for remote TTS
- `mlx-audio` for built-in external bridging across both ASR and TTS

## Provider Config

Providers are registered in `~/.vox/providers.json`:

```json
{
  "providers": [
    {
      "id": "parakeet",
      "kind": "asr",
      "builtin": true,
      "models": ["parakeet:v3"]
    },
    {
      "id": "avspeech",
      "kind": "tts",
      "builtin": true,
      "models": ["avspeech:system"]
    },
    {
      "id": "mlx-audio",
      "kind": "asr",
      "builtin": true,
      "env": {
        "VOX_MLX_AUDIO_PYTHON": "/path/to/venv/bin/python",
        "VOX_MLX_AUDIO_ASR_MODELS": "mlx-community/whisper-large-v3-turbo-asr-fp16,mlx-community/Qwen3-ASR-0.6B-8bit"
      }
    },
    {
      "id": "mlx-audio",
      "kind": "tts",
      "builtin": true,
      "env": {
        "VOX_MLX_AUDIO_PYTHON": "/path/to/venv/bin/python",
        "VOX_MLX_AUDIO_TTS_MODELS": "mlx-community/Soprano-1.1-80M-bf16,mlx-community/Kokoro-82M-4bit",
        "VOX_MLX_AUDIO_TTS_DEFAULT_VOICE": "af_heart"
      }
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Unique identifier for this provider. |
| `kind` | `"asr" \| "tts"` | No | Provider kind. Defaults to `asr` if omitted. |
| `builtin` | `boolean` | No | If `true`, Vox uses its bundled implementation for the given `id`. |
| `command` | `string[]` | No | Executable and arguments Vox will spawn for an external provider. |
| `models` | `string[]` | No | Model IDs this provider serves. Optional when the provider reports models dynamically. |
| `env` | `Record<string, string>` | No | Extra environment variables passed to the provider process. |

Notes:

- Register ASR and TTS as separate entries even when they share the same `id`.
- `models` is optional for external providers now. Vox can call `models()` and route dynamically from the returned list.
- If `providers.json` contains only ASR entries, Vox falls back to default TTS providers. The inverse is also true.

## Protocol Methods

All communication uses newline-delimited JSON-RPC 2.0 over stdin (requests from Vox) and stdout (responses from the provider).

### `models`

List available models for the provider kind.

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
        "id": "mlx-community/whisper-large-v3-turbo-asr-fp16",
        "name": "whisper-large-v3-turbo-asr-fp16",
        "backend": "mlx-audio",
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
{ "jsonrpc": "2.0", "id": 2, "method": "install", "params": { "modelId": "mlx-community/Kokoro-82M-4bit" } }
```

The provider can emit progress notifications on stdout during installation or preload:

```json
{ "jsonrpc": "2.0", "method": "progress", "params": { "modelId": "mlx-community/Kokoro-82M-4bit", "progress": 0.5, "status": "loading" } }
```

**Response:** a model info object matching the shape returned by `models`.

### `preload`

Load a model into memory so subsequent requests start faster.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 3, "method": "preload", "params": { "modelId": "mlx-community/Soprano-1.1-80M-bf16" } }
```

**Response:** a model info object with `preloaded: true`.

## ASR Methods

### `transcribe`

Transcribe an audio file.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 4, "method": "transcribe", "params": { "modelId": "mlx-community/whisper-large-v3-turbo-asr-fp16", "path": "/tmp/audio.wav" } }
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "modelId": "mlx-community/whisper-large-v3-turbo-asr-fp16",
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
    },
    "words": [
      { "word": "Hello", "start": 0.12, "end": 0.44, "confidence": 0.99 },
      { "word": "world", "start": 0.45, "end": 0.71, "confidence": 0.98 }
    ]
  }
}
```

## TTS Methods

### `voices`

List available voices for a model. If `modelId` is omitted, Vox may call `voices` across multiple models and merge the results.

**Request:**

```json
{ "jsonrpc": "2.0", "id": 5, "method": "voices", "params": { "modelId": "mlx-community/Kokoro-82M-4bit" } }
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "voices": [
      {
        "id": "af_heart",
        "name": "af_heart",
        "language": "en-US",
        "backend": "mlx-audio",
        "modelId": "mlx-community/Kokoro-82M-4bit",
        "available": true,
        "default": true
      }
    ]
  }
}
```

### `synthesize`

Generate audio from text.

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "synthesize",
  "params": {
    "modelId": "mlx-community/Soprano-1.1-80M-bf16",
    "input": "Hello from Vox",
    "voiceId": "af_heart",
    "format": "wav",
    "speed": 1.0
  }
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "modelId": "mlx-community/Soprano-1.1-80M-bf16",
    "voiceId": "af_heart",
    "format": "wav",
    "contentType": "audio/wav",
    "audioBase64": "<base64 wav data>",
    "elapsedMs": 418,
    "metrics": {
      "audioDurationMs": 1024,
      "characterCount": 14,
      "modelCheckMs": 0,
      "modelLoadMs": 0,
      "voiceResolveMs": 1,
      "synthesisMs": 363,
      "totalMs": 418
    }
  }
}
```

## Metrics Contract

Providers must return stage timings in the `metrics` object of every `transcribe` or `synthesize` response. These feed into Vox telemetry tagged with `modelId`, `route`, and, for TTS, `voiceId`.

### ASR metrics

Required fields:

| Field | Type | Description |
|-------|------|-------------|
| `inferenceMs` | `number` | Time spent running the model. |
| `totalMs` | `number` | Wall-clock time for the entire request. |

Optional but recommended:

| Field | Type | Description |
|-------|------|-------------|
| `modelLoadMs` | `number` | Time loading the model (0 if already preloaded). |
| `audioLoadMs` | `number` | Time reading the audio file from disk. |
| `audioPrepareMs` | `number` | Time resampling or converting the audio. |
| `fileCheckMs` | `number` | Time validating the audio file exists and is readable. |
| `modelCheckMs` | `number` | Time checking the model is installed and ready. |
| `audioDurationMs` | `number` | Duration of the input audio. |

### TTS metrics

Required fields:

| Field | Type | Description |
|-------|------|-------------|
| `totalMs` | `number` | Wall-clock time for the entire request. |

Optional but recommended:

| Field | Type | Description |
|-------|------|-------------|
| `synthesisMs` | `number` | Time spent generating audio once the model is running. |
| `inferenceMs` | `number` | Accepted as a fallback alias for `synthesisMs`. |
| `modelLoadMs` | `number` | Time loading the model (0 if already preloaded). |
| `modelCheckMs` | `number` | Time checking the model is installed and ready. |
| `voiceResolveMs` | `number` | Time resolving the requested voice. |
| `audioDurationMs` | `number` | Duration of the synthesized audio. |
| `outputBytes` | `number` | Number of encoded output bytes. |
| `characterCount` | `number` | Length of the input text. |

## What Vox handles

Providers only deal with models plus transcription or synthesis. The runtime handles everything else:

- Mic permissions and capture -- ASR providers receive a WAV file path
- Audio format normalization for ASR input
- Playback handoff -- TTS providers return audio bytes and Vox hands them back to the caller
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

  if (req.method === "voices") {
    respond(req.id, {
      voices: [
        {
          id: "default",
          name: "Default",
          backend: "custom-tts",
          modelId: req.params?.modelId ?? "my-tts:v1",
          available: true,
          default: true,
        },
      ],
    });
  }

  if (req.method === "synthesize") {
    const audioBase64 = await mySynthesize(req.params.input);
    respond(req.id, {
      modelId: req.params.modelId,
      voiceId: req.params.voiceId ?? "default",
      format: "wav",
      contentType: "audio/wav",
      audioBase64,
      elapsedMs: 120,
      metrics: { synthesisMs: 110, totalMs: 120 },
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
    {
      "id": "my-provider",
      "kind": "asr",
      "command": ["bun", "run", "minimal-provider.ts"],
      "models": ["my-model:v1"]
    },
    {
      "id": "my-tts",
      "kind": "tts",
      "command": ["bun", "run", "minimal-provider.ts"],
      "models": ["my-tts:v1"]
    }
  ]
}
```

Then select it via CLI or SDK by specifying the target model ID.

## Provider lifecycle

Vox spawns the provider process on first use. It stays alive for the daemon's lifetime. If it crashes, Vox restarts it on the next request.

Providers should be stateless between requests. The provider process can keep model weights in memory, but Vox assumes nothing about that state -- a crash and restart must not break anything.
