# vox

> Local-first voice stack for Apple apps, web companions, and developer tools

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- Always solve root cause before looking for workarounds and quick fixes.
- Vox is an Apple-platform voice stack: Swift owns the embeddable engine surface and the companion transport surface.
- The Bun workspace contains the CLI and TypeScript clients, which communicate with voxd in companion mode.
- Performance instrumentation is first-class: preserve clientId, route, and modelId dimensions in telemetry.
- Warm-up semantics are part of the public runtime surface and should remain usable for multi-client integrations.

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| Daemon | `swift/Sources/voxd/main.swift` | |
| Service | `swift/Sources/VoxService/` | |
| Engine | `swift/Sources/VoxEngine/` | |
| Core | `swift/Sources/VoxCore/` | |
| Sdk | `packages/client/src/` | |
| Cli | `packages/cli/src/index.ts` | |
| Docs | `docs/` | |
| Site | `site/` | |

## Quick Navigation

- Working with **swift/Sources/VoxEngine/***? → Keep instrumentation and model lifecycle explicit; do not hide warm-up cost in opaque helpers.
- Working with **swift/Sources/VoxService/***? → Preserve multi-client semantics; clientId should remain available anywhere latency or session ownership matters.
- Working with **packages/client/***? → SDK APIs should expose the runtime capabilities directly, including metrics and warm-up surfaces.
- Working with **packages/cli/***? → CLI commands are also operator tools; prefer clear terminal output and measurable benchmarks.
- Working with **site/***? → Maintain the clean, restrained Vox visual language. Avoid generic startup landing page patterns.

## Provider Protocol

> How external STT and TTS engines plug into Vox via JSON-RPC over stdin/stdout.

# Provider Protocol

Vox separates the runtime (mic capture, sessions, routing, telemetry, playback handoff) from the speech engine. Engines are called _providers_ -- external processes or built-in bridges that speak JSON-RPC over stdin/stdout.

Providers can serve either:

- ASR / STT — accept audio and return text
- TTS — accept text and return audio

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
- Provider execution capacity and backpressure -- requests are not globally serialized by default

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

## Overview

# Vox Overview

Vox is a local-first voice stack for macOS and iOS. It supports both speech-to-text (STT / ASR) and text-to-speech (TTS) in two first-class integration modes:

- Embed mode — Apple apps link Vox's Swift packages directly and keep speech in and speech out in process.
- Companion mode — `voxd` exposes the same capabilities over local JSON-RPC and HTTP when web or shared-process access is useful.

Main surfaces:

- Swift packages — `VoxCore`, `VoxEngine`, `VoxService`, `VoxBridge` for embedded Apple app integrations.
- `voxd` — Vox Companion, the Swift daemon. Warm-up, telemetry, bridge transport, shared-process coordination.
- `@voxd/sdk` — TypeScript SDK for Bun/Node and other companion-connected integrations. WebSocket JSON-RPC to `voxd`.
- `@voxd/client` — Browser SDK. HTTP bridge to the Vox Companion for web apps.
- `@voxd/cli` — Bun CLI. Health checks, model management, transcription, synthesis, voices, warm-up, and benchmarks.

## Why it exists

Most voice stacks hide lifecycle, warm-up, and latency. Vox keeps them visible:

- Model stays local
- STT and TTS stay explicit runtime capabilities instead of hidden backend switches
- Warm-up is an explicit API
- Latency dimensions (`clientId`, `route`, `modelId`) are preserved
- Runtime is observable from day one

## Repository layout

- `swift/` — VoxCore, VoxEngine, VoxService, VoxBridge, voxd companion
- `packages/client/` — `@voxd/sdk` (TypeScript SDK)
- `packages/web-client/` — `@voxd/client` (browser SDK)
- `packages/cli/` — `@voxd/cli` (Bun CLI)
- `docs/` — Dewey source content
- `site/` — website and docs UI

## Design principles

1. Root cause over workaround.
2. Warm-up is part of the product, not an implementation detail.
3. Instrumentation is part of the API surface.
4. Multi-client support stays visible in the protocol and telemetry.

## How it fits together

Apple app teams embed the Swift packages directly and keep the same provider, warm-up, and telemetry semantics in process. Web apps use `@voxd/client` against Vox Companion, Bun and Node tools use `@voxd/sdk`, and operators use `vox` to check health, list voices, transcribe, synthesize, warm models, and benchmark both speech paths. Companion mode lets `voxd` stay warm across browser integrations, local tools, and other shared-process clients.

## Workflows

These examples assume `vox` is on your `PATH`. In a repo checkout, replace `vox` with `bun packages/cli/src/index.ts`.

```bash
# Build and verify
bun install && bun run build
vox daemon start
vox doctor

# Speech to text
vox warmup start parakeet:v3
vox transcribe file --model parakeet:v3 --metrics --timestamps /tmp/sample.wav

# Text to speech
vox voices --model avspeech:system
vox speak --model avspeech:system --metrics "Hello from Vox"

# Compare warm-path performance
vox transcribe bench --model parakeet:v3 /tmp/sample.wav 5
vox speak bench --model avspeech:system "Hello from Vox" 5
vox perf dashboard --client vox-cli
```

## Quickstart

# Quickstart

## Prerequisites

- macOS 26+ or iOS 26+ for Apple SDK consumers
- Bun
- Swift 6.2+

## Install and verify

```bash
bun add -g @voxd/cli
vox daemon start
vox doctor       # expect ready: true
```

If you are running from a repo checkout instead of a global install, replace `vox` with `bun packages/cli/src/index.ts`.

## Speech to text

```bash
vox warmup start parakeet:v3
vox transcribe file --model parakeet:v3 /path/to/audio.wav --metrics --timestamps
vox transcribe bench --model parakeet:v3 /path/to/audio.wav 5
```

Warm-up skips cold-start cost. `transcribe file` prints transcript text, stage timings, and optional word-level timestamps. `bench` gives you warm-path variance for the same clip.

## Text to speech

```bash
vox voices --model avspeech:system
vox speak --model avspeech:system --metrics "Hello from Vox"
vox speak bench --model avspeech:system "Hello from Vox" 5
```

`voices` shows available presets for the selected model. `speak` synthesizes audio immediately and prints synthesis metrics when `--metrics` is set. `speak bench` repeats the same request so you can compare warm-path TTS behavior.

## External providers

For non-Parakeet ASR or non-system TTS, add entries to `~/.vox/providers.json` and then pass the returned model ID with `--model`.

The [Provider Protocol](./providers.md) includes built-in `mlx-audio` examples for both STT and TTS.

## Measure and inspect

```bash
vox perf dashboard --client vox-cli
vox logs daemon --tail 80
vox transcribe status
```

`perf dashboard` shows latency samples by client, route, and model. Use `logs daemon` and `transcribe status` when a live session gets stuck or the mic is busy.

## Common failure cases

- Missing ASR model: `vox models list` then `vox models install`
- TTS provider or voice issue: `vox voices --model <id>` then retry `vox speak --model <id> ...`
- External TTS model install/setup: follow the provider's own setup flow, such as the `mlx-audio` environment in `~/.vox/providers.json`
- Wrong or missing voice: `vox voices --model <id>`
- External provider missing dependencies: verify `~/.vox/providers.json` and any referenced interpreter or API key
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a `transcribe` or `speak` command first so the runtime emits samples
- Stuck live session: `vox transcribe status` then `vox transcribe cancel`
- Need daemon logs: `vox logs daemon --tail 120`

## Next steps

If you are integrating Vox into a macOS or iOS app, read the [Swift Embed Guide](./apple-embed.md).

If you are wiring external STT or TTS engines into Vox Companion, read the [Provider Protocol](./providers.md).

Try the [sample app](https://github.com/arach/vox/tree/main/examples/transcribe-tui) -- a terminal transcription tool that connects to the runtime, warms the model, and shows timing bars for each file.

## Swift Embed Guide

> Agent-oriented instructions for integrating Vox directly into macOS and iOS apps such as Linea.

# Swift Embed Guide

Use this guide when you are integrating Vox into a macOS or iOS app and want the app to call Vox directly in process. This is the default path for Apple-native clients such as Linea.

## Choose the integration mode

- Use embed mode when the caller is app code running inside a macOS or iOS process.
- Use Vox Companion (`voxd`) when the caller lives outside the app process, such as a web app, browser extension, or Bun/Node tool.
- Keep `voxd` out of the Apple app itself. If the goal is in-process app integration, embed the Swift packages directly instead.

## What embed mode is today

The current public embed surface is low-level but usable:

- ASR: `EngineManager`
- TTS: `TTSEngineManager`, `SynthesisRequest`
- outputs: `TranscriptionOutput`, `SynthesisOutput`, `TTSVoiceInfo`
- telemetry: `PerformanceRecorder`, `PerformanceSample`
- provider composition: `ProviderRegistry`, `TTSProviderRegistry`, `ProvidersConfig`, `ProviderEntry`

There is not yet a polished one-object Apple SDK facade. Agents should usually create a thin app-local wrapper such as `VoiceService` or `LineaVoiceStack` and keep raw Vox types behind that boundary.

## Package setup

For a sibling repo during local development, prefer a local SwiftPM dependency:

```swift
.package(path: "../vox/swift")
```

Add these product dependencies to the app target:

- `VoxCore`
- `VoxEngine`

Only add `VoxService` or `VoxBridge` if the app intentionally embeds companion/runtime behavior. That is not the default Apple app path.

## Minimal local-first service

```swift
import Foundation
import VoxCore
import VoxEngine

actor LineaVoiceStack {
    private let clientId: String
    private let asr: EngineManager
    private let tts: TTSEngineManager
    private let performance = PerformanceRecorder()

    init(clientId: String = "linea-ios") {
        self.clientId = clientId
        self.asr = EngineManager()      // Parakeet
        self.tts = TTSEngineManager()   // AVSpeechSynthesizer
    }

    func warmup() async throws {
        _ = try await asr.preload(modelId: "parakeet:v3") { _ in }
        _ = try await tts.preload(modelId: TTSDefaults.modelId, voiceId: nil) { _ in }
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionOutput {
        let output = try await asr.transcribe(url: fileURL, modelId: "parakeet:v3")

        await performance.record(
            PerformanceSample(
                clientId: clientId,
                route: "transcribe.file",
                modelId: output.modelId,
                outcome: "ok",
                textLength: output.text.count,
                metrics: output.metrics.performanceMetrics
            )
        )

        return output
    }

    func synthesize(text: String, voiceId: String? = nil) async throws -> SynthesisOutput {
        let output = try await tts.synthesize(
            SynthesisRequest(
                text: text,
                modelId: TTSDefaults.modelId,
                voiceId: voiceId
            )
        )

        await performance.record(
            PerformanceSample(
                clientId: clientId,
                route: "synthesize.generate",
                modelId: output.modelId,
                voiceId: output.voiceId,
                outcome: "ok",
                textLength: text.count,
                metrics: output.metrics.performanceMetrics
            )
        )

        return output
    }
}
```

## App responsibilities

In embed mode, the app still owns:

- microphone permission
- audio capture
- temp-file creation for ASR input
- audio playback for synthesized WAV data
- interruption handling
- product-level state and UX

Today the ASR entrypoint takes a `URL`, not an in-memory audio buffer. Agents should capture audio, write it to a temporary file, then call `transcribe(url:modelId:)`.

TTS returns WAV bytes in `SynthesisOutput.audioData`. Agents should hand that data to the app playback layer, such as `AVAudioPlayer` or `AVAudioEngine`.

## Warm-up

Warm-up must remain explicit.

- ASR warm-up: `EngineManager.preload(modelId:progress:)`
- TTS warm-up: `TTSEngineManager.preload(modelId:voiceId:progress:)`

Do not hide warm-up behind app launch side effects unless the product intentionally wants that behavior. Prefer warming on intent or at a predictable app state transition.

## Telemetry

Companion mode records telemetry automatically. Embed mode does not.

If the app wants parity with Vox Companion telemetry, record samples yourself with `PerformanceRecorder` and preserve these dimensions:

- `clientId`
- `route`
- `modelId`
- `voiceId` for synthesis

Use the same route names Vox Companion uses:

- `transcribe.file`
- `synthesize.generate`

`RuntimePaths.performanceLogURL()` resolves to:

- macOS: `~/.vox/performance.jsonl`
- iOS: `Application Support/Vox/performance.jsonl`

## OpenAI TTS in embed mode

The zero-dependency default is:

- ASR: `EngineManager()` -> `ParakeetProvider()`
- TTS: `TTSEngineManager()` -> `AVSpeechSynthesizerProvider()`

If the app needs remote TTS, create a registry explicitly. Prefer passing secrets in code or app configuration rather than relying on process environment inside an iOS app.

```swift
let ttsConfig = ProvidersConfig(providers: [
    ProviderEntry(
        id: "avspeech",
        kind: .tts,
        builtin: true,
        models: [AVSpeechSynthesizerProvider.modelID]
    ),
    ProviderEntry(
        id: "openai-tts",
        kind: .tts,
        builtin: true,
        models: OpenAITTSProvider.supportedModelIDs,
        env: ["OPENAI_API_KEY": apiKey]
    )
])

let tts = TTSEngineManager(provider: TTSProviderRegistry(config: ttsConfig))
```

## Linea default plan

For the first Linea integration, the default plan should be:

- use embed mode on iOS and macOS
- add `VoxCore` and `VoxEngine`
- wrap Vox in one app-local actor or service
- use `parakeet:v3` for ASR
- use `avspeech:system` for default TTS
- record Vox-compatible telemetry from the app
- introduce OpenAI TTS only if product requirements need remote voices
- use Vox Companion only for web surfaces or cross-process workflows

## What agents should not assume

- There is no public one-object Apple SDK facade yet.
- There is no public embed live-session coordinator yet.
- There is no public embed warm-up coordinator helper.
- Embed mode does not automatically write performance samples.
- Apple apps do not need `@voxd/sdk` or `@voxd/client`.

## First tasks in a sibling app repo

1. Add `../vox/swift` as a local package dependency.
2. Create a single `VoiceService` or `LineaVoiceStack` actor in app code.
3. Warm the ASR and TTS engines explicitly.
4. Feed ASR with file URLs, not raw buffers.
5. Feed TTS output WAV data into the app playback layer.
6. Emit `PerformanceSample` records with stable route names.
7. Keep Companion mode out of the Apple app path unless the feature is genuinely web or cross-process.

## Runtime

# Runtime

## Core Flow

1. A client connects to `voxd` over local WebSocket JSON-RPC.
2. The runtime resolves health, model state, and optional warm-up state.
3. The client triggers file transcription, a live ASR session, one-shot synthesis, or a synthesis session.
4. `VoxEngine` resolves the right ASR or TTS provider and returns transcript text, word timings, or WAV bytes plus stage metrics.
5. The runtime records a tagged performance sample to `~/.vox/performance.jsonl`.
6. The daemon appends operational logs to `~/.vox/logs/voxd.log`.

## Warm-Up

Warm-up is a public API, not a hidden side effect. It applies to both ASR and TTS models.

- `warmup.status` -- check if the model is hot
- `warmup.start` -- warm immediately
- `warmup.schedule` -- warm after a delay

Typical pattern: create a `VoxClient` with a stable `clientId`, warm when the user opens a voice affordance, then transcribe or synthesize once the model is ready.

## File Transcription

`transcribe.file` is best for benchmarks because it takes mic capture out of the measurement. Returns transcript text, word-level timestamps, `modelId`, elapsed time, and stage metrics.

## Synthesis

`synthesize.voices` lists available voices for a TTS model.

`synthesize.generate` returns:

- `modelId`
- `voiceId`
- `format`
- `contentType`
- base64-encoded audio bytes
- elapsed time
- synthesis metrics

Longer-running output flows use:

- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`

## RPC Routes

The runtime exposes these RPC routes:

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`
- `synthesize.voices`
- `synthesize.generate`
- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`
- `warmup.status`
- `warmup.start`
- `warmup.schedule`

## Performance routes

These are the route values currently emitted into `performance.jsonl`:

- `transcribe.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

Cancelled synthesis sessions are currently recorded as `synthesize.startSession` with `outcome: "cancelled"`.

## Live Sessions

Speech sessions are coordinated in `VoxService`. Session ownership ties to both `connectionID` and `clientId`. Stop and cancel are distinct operations. Final transcript events include metrics and word-level timestamps. Synthesis session status includes the selected model and voice. Active session state is inspectable for operator recovery.

## Configuration

Ports and bind address are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VOX_PORT` | `42137` | Daemon WebSocket port |
| `VOX_BRIDGE_PORT` | `43115` | HTTP bridge port |
| `VOX_HOST` | `127.0.0.1` | Bind address for both services |
| `VOX_HOME` | `~/.vox` | Runtime data directory |

CLI flag `--port` takes precedence over env vars for both `voxd` and `voxbridge`.

## Important Swift entry points

- `swift/Sources/voxd/main.swift`
- `swift/Sources/VoxService/VoxRuntimeService.swift`
- `swift/Sources/VoxService/LiveSessionCoordinator.swift`
- `swift/Sources/VoxService/SynthesisSessionCoordinator.swift`
- `swift/Sources/VoxService/WarmupCoordinator.swift`
- `swift/Sources/VoxEngine/ProviderRegistry.swift`
- `swift/Sources/VoxEngine/TTSProviderRegistry.swift`

## Sdk

# SDK (Companion Client)

> Apple apps on macOS and iOS can embed Vox's Swift packages directly. `@voxd/sdk` is the TypeScript client for Bun/Node tools and other companion-connected integrations that connect to `voxd` over local WebSocket JSON-RPC. For web apps or browser extensions, use [`@voxd/client`](./web-integration.md) instead — it talks to Vox Companion over HTTP.

`packages/client/` -- connects to `voxd` when you want out-of-process access to models, voices, warm-up, transcription, synthesis, and stage metrics.

## Example

```ts
import { VoxClient } from "@voxd/sdk";

const client = new VoxClient({ clientId: "menu-bar" });

await client.connect();
await client.scheduleWarmup("parakeet:v3", 500);

const transcript = await client.transcribeFile("/tmp/sample.wav", "parakeet:v3");
const voices = await client.listVoices("avspeech:system");
const speech = await client.synthesize("Hello from Vox", {
  modelId: "avspeech:system",
  voiceId: voices[0]?.id,
  format: "wav",
});

console.log(transcript.text);
console.log(transcript.metrics?.inferenceMs);
console.log(transcript.words);
console.log(speech.audioBytes);
console.log(speech.metrics?.synthesisMs);

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
  getLiveSessionStatus(): Promise<LiveSessionStatus | null>;
  cancelLiveSession(sessionId?: string): Promise<{ cancelled: boolean; sessionId: string }>;
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

## Synthesis result shape

```ts
interface SynthesisResult {
  modelId: string;
  voiceId: string;
  format: string;
  contentType: string;
  audio: Uint8Array;
  audioBytes: number;
  elapsedMs: number;
  metrics?: SynthesisMetrics;
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
  // - Voice mismatch: inspect `client.listVoices(modelId)`
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
- call `listVoices(modelId)` before pinning a TTS voice in product code
- benchmark with representative audio clips and read `inferenceMs` separately from `totalMs`
- preserve raw transcription and synthesis metrics in your own telemetry if the app already exports traces

## Web-integration

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

## Observability

# Observability

Telemetry is built into the runtime for both transcription and synthesis. Each performance sample includes:

- `clientId`
- `route`
- `modelId`
- `voiceId` for synthesis routes when a voice is selected
- `outcome`
- nested `metrics`

## Metrics

Transcription metrics:

- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `audioDurationMs`

Synthesis metrics:

- `modelCheckMs`
- `modelLoadMs`
- `voiceResolveMs`
- `synthesisMs`
- `totalMs`
- `audioDurationMs`
- `outputBytes`
- `characterCount`

Derived values: `realtimeFactor`, warm vs cold from `modelLoadMs`, audio-to-text speed from `audioDurationMs / inferenceMs`, and text-to-audio speed from `audioDurationMs / synthesisMs`.

## Storage

The runtime appends JSON lines to:

```text
~/.vox/performance.jsonl
```

The CLI dashboard reads from this file. You can also export it to another metrics backend.

Current emitted performance routes:

- `transcribe.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

Cancelled synthesis sessions are recorded under `synthesize.startSession` with `outcome: "cancelled"`.

## Operator Commands

```bash
vox transcribe file --metrics /tmp/sample.wav
vox transcribe bench /tmp/sample.wav 5
vox speak --metrics "hello world"
vox speak bench "hello world" 5
vox perf dashboard
vox perf dashboard --client vox-cli
```

## Reading the numbers

`inferenceMs`, `synthesisMs`, and `totalMs` measure different things.

- For ASR, `inferenceMs` is how fast the hot model ran.
- For TTS, `synthesisMs` is how long audio generation took once the request was inside the model.
- `totalMs` is what the user experienced end-to-end.

## Example sample

```json
{
  "timestamp": "2026-04-25T17:54:26Z",
  "clientId": "menu-bar",
  "route": "synthesize.generate",
  "modelId": "avspeech:system",
  "voiceId": "com.apple.voice.compact.en-US.Samantha",
  "outcome": "ok",
  "textLength": 14,
  "metrics": {
    "audioDurationMs": 1240,
    "synthesisMs": 182,
    "inferenceMs": 182,
    "totalMs": 196
  }
}
```

## Dashboard tips

- Only compare clients when the prompt or audio shape is similar.
- Use `inferenceMs` for loaded-model ASR speed.
- Use `synthesisMs` for loaded-model TTS speed.
- Use `totalMs` for end-user latency.
- Large `modelLoadMs` spikes are warm-up events, not inference regressions.

## Architecture

# Architecture

## Layers

### VoxCore

Shared runtime types and utilities:

- runtime metadata
- transcription and synthesis metrics
- performance samples
- filesystem paths
- trace utilities

### VoxEngine

Model-facing speech layer:

- model installation and preload
- ASR provider routing and audio preparation
- TTS provider routing and voice discovery
- Parakeet inference
- AVSpeech, OpenAI, and external synthesis backends
- stage-level timing

### VoxService

Daemon-side orchestration:

- JSON-RPC bridge
- live session coordination
- synthesis session coordination
- microphone recording
- warm-up scheduling
- performance sample recording

### TypeScript SDK

`@voxd/sdk` — health, models, voices, warm-up, file transcription, synthesis, live sessions, metrics parsing.

### Browser SDK

`@voxd/client` — probe, transcribe, align, live sessions over the HTTP bridge.

### CLI

`@voxd/cli` — operator tool. Doctor, daemon lifecycle, model management, voices, transcription, synthesis, benchmarks, dashboards.

## Ownership

| Surface | Owns |
|---------|------|
| Swift runtime | Daemon lifecycle, audio prep, model lifecycle, provider routing, transcription, synthesis, perf recording |
| TypeScript SDK | Connection lifecycle, typed request/response shapes, live-session ergonomics, transcription and synthesis metric parsing |
| Browser SDK | Companion discovery, audio upload, job polling, live sessions over HTTP bridge |
| CLI | Operator commands, terminal output (human and machine), warm-up controls, transcription, synthesis, dashboards |
| Site and docs | Architecture docs, onboarding, OG images, landing page |

## Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares ASR input or TTS requests and dispatches them to the selected provider
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection

## Api

# API

Public protocol and SDK-facing type shapes.

## RPC Methods

### Health and Runtime

- `health`
- `doctor.run`

### Models

- `models.list`
- `models.install`
- `models.preload`

### Warm-Up

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

### Transcription

- `transcribe.file`
- `transcribe.startSession`
- `transcribe.sessionStatus`
- `transcribe.stopSession`
- `transcribe.cancelSession`

### Synthesis

- `synthesize.voices`
- `synthesize.generate`
- `synthesize.startSession`
- `synthesize.sessionStatus`
- `synthesize.cancel`

## Performance samples

These fields are present on every performance sample recorded to `~/.vox/performance.jsonl`.

```ts
type PerformanceRoute =
  | "transcribe.file"
  | "transcribe.live"
  | "synthesize.generate"
  | "synthesize.startSession"
  | string;
```

```ts
interface PerformanceSample {
  timestamp: string;
  clientId: string;
  route: PerformanceRoute;
  modelId: string;
  voiceId?: string;
  outcome: "ok" | "error" | "cancelled" | string;
  textLength: number;
  error?: string;
  metrics?: PerformanceMetrics;
}

interface PerformanceMetrics {
  traceId: string;
  audioDurationMs: number;
  wasPreloaded: boolean;
  modelCheckMs: number;
  modelLoadMs: number;
  inferenceMs: number;
  totalMs: number;
  inputBytes?: number;
  fileCheckMs?: number;
  audioLoadMs?: number;
  audioPrepareMs?: number;
  characterCount?: number;
  outputBytes?: number;
  voiceResolveMs?: number;
  synthesisMs?: number;
  realtimeFactor?: number;
}
```

Current emitted performance routes:

- `transcribe.file`
- `transcribe.live`
- `synthesize.generate`
- `synthesize.startSession`

## Core TypeScript SDK Entry Points

### `VoxClient`

- `connect()`
- `disconnect()`
- `doctor()`
- `listModels()`
- `listVoices()`
- `installModel()`
- `preloadModel()`
- `getWarmupStatus()`
- `startWarmup()`
- `scheduleWarmup()`
- `transcribeFile()`
- `synthesize()`
- `getLiveSessionStatus()`
- `cancelLiveSession()`
- `createLiveSession()`

### `FileTranscriptionResult`

- `modelId`
- `text`
- `elapsedMs`
- `metrics`
- `words`

### `SynthesisResult`

- `modelId`
- `voiceId`
- `format`
- `contentType`
- `audio`
- `audioBytes`
- `elapsedMs`
- `metrics`

### `TranscriptionMetrics`

- `traceId`
- `audioDurationMs`
- `inputBytes`
- `wasPreloaded`
- `fileCheckMs`
- `modelCheckMs`
- `modelLoadMs`
- `audioLoadMs`
- `audioPrepareMs`
- `inferenceMs`
- `totalMs`
- `realtimeFactor`

### `SynthesisMetrics`

- `traceId`
- `characterCount`
- `audioDurationMs`
- `outputBytes`
- `wasPreloaded`
- `modelCheckMs`
- `modelLoadMs`
- `voiceResolveMs`
- `synthesisMs`
- `inferenceMs`
- `totalMs`
- `realtimeFactor`

## Interface shapes

```ts
interface TranscriptionMetrics {
  traceId: string;
  audioDurationMs?: number;
  inputBytes?: number;
  wasPreloaded?: boolean;
  fileCheckMs?: number;
  modelCheckMs?: number;
  modelLoadMs?: number;
  audioLoadMs?: number;
  audioPrepareMs?: number;
  inferenceMs?: number;
  totalMs?: number;
  realtimeFactor?: number;
}

interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}

interface SynthesisOptions {
  modelId?: string;
  voiceId?: string;
  format?: string;
  speed?: number;
  instructions?: string;
}

interface SynthesisMetrics {
  traceId: string;
  characterCount: number;
  audioDurationMs: number;
  outputBytes: number;
  wasPreloaded: boolean;
  modelCheckMs: number;
  modelLoadMs: number;
  voiceResolveMs: number;
  synthesisMs: number;
  inferenceMs: number;
  totalMs: number;
  realtimeFactor: number;
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
}
```

## Warm-up states

```ts
type WarmupState = "idle" | "scheduled" | "warming" | "ready" | "failed";
```

Apps use this to tell whether the runtime is cold, warming, or ready for hot-path speech.

---
Generated by [Dewey 0.3.4](https://github.com/arach/dewey) | Last updated: 2026-04-25
