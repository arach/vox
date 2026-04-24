# VOX-002: Synthesis Contract

Status: Draft
Date: 2026-04-24
Owners: Vox engine, bridge, SDK, and CLI

## Summary

VOX-002 defines the Phase 1 synthesis surface for Vox.

Goal: make speech output a first-class sibling to transcription instead of a sidecar stack. Vox keeps one provider model, one warm-up surface, one telemetry log, and one transport contract whenever voice runs out of process.

Phase 1 adds:

- `TTSProvider` as the synthesis sibling to `ASRProvider`
- built-in `AVSpeechSynthesizerProvider` for offline Apple speech
- built-in `OpenAITTSProvider` for remote speech generation via `POST /v1/audio/speech`
- `synthesize.*` JSON-RPC routes on `voxd`
- NDJSON audio streaming routes on the local HTTP bridge
- CLI and TypeScript SDK synthesis APIs that mirror the existing transcription ergonomics

## Context

Vox already owns the input half of the stack:

- Swift packages own the embeddable provider, warm-up, telemetry, and live-capture surfaces for Apple apps
- `voxd` manages the companion transport, warm-up, telemetry, and live capture when Vox runs out of process
- `VoxEngine` exposes provider-backed transcription and synthesis
- `@voxd/sdk` mirrors the daemon over local WebSocket JSON-RPC
- `vox` exposes operator-friendly runtime commands

Synthesis should reuse those same shapes instead of inventing one stack for embed mode and another for companion mode.

## Goals

- Keep Swift as the owner of the embeddable engine surface and the companion transport surface.
- Preserve `clientId`, `route`, and `modelId` as telemetry dimensions.
- Add `voiceId` as a required synthesis telemetry dimension.
- Keep warm-up a public capability instead of an implicit side effect.
- Mirror the transcription-side route and session patterns wherever the semantics line up.
- Keep the browser bridge origin allowlist and NDJSON transport story intact.

## Non-Goals

- Linea iOS integration details.
- Tailscale or remote companion discovery.
- Pairing flows for mobile-to-daemon communication.
- Retiring old branding in Linea.
- Realtime bidirectional speech-to-speech.

## Integration Modes

Embed mode and companion mode are both first-class Vox deployments.

Embed mode is the in-process Apple app story:

- macOS and iOS apps link Vox's Swift packages directly
- no local daemon is required
- provider behavior, warm-up semantics, and telemetry dimensions stay the same

Companion mode is the out-of-process and web-facing story:

- `voxd` exposes JSON-RPC and HTTP bridge routes for web apps and shared local tooling
- route names in this document are frozen for those out-of-process clients
- embed-mode APIs should reuse the same semantic names in telemetry and docs wherever possible

## JSON-RPC Contract

### Stable synthesis routes

Phase 1 freezes these companion routes:

- `synthesize.voices`
- `synthesize.generate`
- `synthesize.sessionStatus`
- `synthesize.startSession`
- `synthesize.cancel`

Telemetry route values must match these names exactly.

### `synthesize.voices`

List available voices. When `modelId` is omitted, Vox returns voices across registered synthesis models.

Request:

```json
{
  "method": "synthesize.voices",
  "params": {
    "modelId": "avspeech:system",
    "clientId": "vox-cli"
  }
}
```

Response:

```json
{
  "voices": [
    {
      "id": "com.apple.speech.synthesis.voice.Alex",
      "name": "Alex",
      "language": "en-US",
      "backend": "avspeech",
      "modelId": "avspeech:system",
      "available": true,
      "default": true
    }
  ]
}
```

### `synthesize.generate`

Unary synthesis request analogous to `transcribe.file`.

Request:

```json
{
  "method": "synthesize.generate",
  "params": {
    "clientId": "vox-cli",
    "text": "Hello world",
    "modelId": "avspeech:system",
    "voiceId": "com.apple.speech.synthesis.voice.Alex",
    "format": "wav"
  }
}
```

Response:

```json
{
  "modelId": "avspeech:system",
  "voiceId": "com.apple.speech.synthesis.voice.Alex",
  "format": "wav",
  "contentType": "audio/wav",
  "audioBase64": "<base64 wav bytes>",
  "audioBytes": 48244,
  "elapsedMs": 142,
  "metrics": {
    "traceId": "ab12cd34",
    "characterCount": 11,
    "audioDurationMs": 820,
    "outputBytes": 48244,
    "wasPreloaded": true,
    "modelCheckMs": 1,
    "modelLoadMs": 0,
    "voiceResolveMs": 1,
    "synthesisMs": 121,
    "inferenceMs": 121,
    "totalMs": 142,
    "realtimeFactor": 0.1476
  }
}
```

Rules:

- `text` is required.
- `format` is fixed to `wav` in Phase 1.
- `voiceId` is optional; the provider may choose its default voice.
- `synthesize.generate` does not implicitly call `warmup.start`.

### Streaming session routes

Phase 1 keeps one streaming synthesis session at a time, matching the current live-transcription concurrency policy.

`synthesize.startSession` opens a streaming response and emits:

- `session.state`
- `session.audio`
- `session.final`

`synthesize.sessionStatus` returns the active session or `null`.

`synthesize.cancel` cancels the active session or a specific `sessionId`.

Session status shape:

```json
{
  "session": {
    "sessionId": "speech_123",
    "connectionId": "conn_456",
    "clientId": "vox-web",
    "modelId": "avspeech:system",
    "voiceId": "alloy",
    "textLength": 11,
    "startedAt": "2026-04-24T15:10:00Z",
    "state": "processing"
  }
}
```

### Session event envelope

`synthesize.startSession` uses the same event envelope style as `transcribe.startSession`.

State event:

```json
{
  "event": "session.state",
  "data": {
    "sessionId": "speech_123",
    "state": "processing",
    "previous": "starting"
  }
}
```

Audio chunk event:

```json
{
  "event": "session.audio",
  "data": {
    "sessionId": "speech_123",
    "sequence": 0,
    "modelId": "avspeech:system",
    "voiceId": "alloy",
    "format": "wav",
    "contentType": "audio/wav",
    "audioBase64": "<base64 chunk>",
    "audioBytes": 24576
  }
}
```

Final event:

```json
{
  "event": "session.final",
  "data": {
    "sessionId": "speech_123",
    "modelId": "avspeech:system",
    "voiceId": "alloy",
    "format": "wav",
    "contentType": "audio/wav",
    "audioBytes": 48244,
    "elapsedMs": 142,
    "metrics": {
      "traceId": "ab12cd34",
      "characterCount": 11,
      "audioDurationMs": 820,
      "outputBytes": 48244,
      "wasPreloaded": true,
      "modelCheckMs": 1,
      "modelLoadMs": 0,
      "voiceResolveMs": 1,
      "synthesisMs": 121,
      "inferenceMs": 121,
      "totalMs": 142,
      "realtimeFactor": 0.1476
    }
  }
}
```

Phase 1 note:

- providers may finish generation before the first `session.audio` event is emitted
- the bridge still streams NDJSON chunks, but the contract does not promise token-by-token or sample-by-sample realtime output yet

## Busy Semantics

Phase 1 synthesis streaming is single-session:

- only one `synthesize.startSession` may be active at a time
- a second start request fails with `synthesis_session_busy`
- unary `synthesize.generate` remains available independently of streaming session status

## Cancel Semantics

Synthesis has `cancel`, not `stop`.

Rationale:

- transcription has a meaningful `stop` because it preserves recorded audio and continues processing
- synthesis has no capture phase to preserve
- the only meaningful control-plane terminal action is immediate cancellation

`synthesize.cancel` means:

- cancel provider work immediately
- end the streaming session
- do not emit more `session.audio` events
- mark the session as `cancelled`

Response:

```json
{
  "cancelled": true,
  "sessionId": "speech_123"
}
```

## Warm-Up Contract

Warm-up remains public and model-addressed:

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

Rules:

- synthesis models participate in the same warm-up coordinator as ASR models
- callers warm by `modelId`, not by route-specific private hooks
- `synthesize.generate` does not hide warm-up
- `synthesize.startSession` may call `warmup.start` once the session begins, matching the existing `transcribe.startSession` behavior

## Telemetry Contract

Every synthesis request that reaches execution must append a performance sample to `~/.vox/performance.jsonl`.

Required top-level fields:

- `clientId`
- `route`
- `modelId`
- `voiceId`
- `outcome`

Metrics object:

```json
{
  "traceId": "ab12cd34",
  "audioDurationMs": 820,
  "wasPreloaded": true,
  "modelCheckMs": 1,
  "modelLoadMs": 0,
  "voiceResolveMs": 1,
  "synthesisMs": 121,
  "inferenceMs": 121,
  "totalMs": 142,
  "characterCount": 11,
  "outputBytes": 48244,
  "realtimeFactor": 0.1476
}
```

Notes:

- `inferenceMs` remains present so operator tooling can compare synthesis and transcription with a shared latency vocabulary
- synthesis also exposes `synthesisMs` explicitly because the operation is speech generation, not transcription inference

## HTTP Bridge Contract

Phase 1 bridge routes:

- `GET /voices`
- `GET /speak`
- `POST /speak`
- `POST /speak/cancel`

Rules:

- all synthesis bridge routes reuse the existing origin allowlist
- `POST /speak` returns `application/x-ndjson` over chunked transfer encoding
- bridge event payloads preserve the daemon event names from `synthesize.startSession`

Example `POST /speak` body:

```json
{
  "clientId": "vox-web",
  "text": "Hello world",
  "modelId": "avspeech:system",
  "voiceId": "alloy",
  "format": "wav"
}
```

## Error Taxonomy

Phase 1 uses string error messages over JSON-RPC and HTTP bridge responses.

Frozen errors:

- `Missing text`
- `synthesis_session_busy`
- `No active synthesis session`
- `Unsupported synthesis model: <id>`
- `Unsupported voice: <id>`
- `Unsupported synthesis format: <format>`

Provider-specific failures may surface their own strings as long as they remain operator-readable.

## CLI and SDK Expectations

The public client surfaces should mirror transcription ergonomics:

- CLI: `vox speak`, `vox speak bench`, `vox voices list`
- SDK: `client.synthesize(text, options)` and `client.listVoices(modelId?)`
- Apple embed mode should map to the same model, voice, warm-up, and telemetry semantics even when it does not speak JSON-RPC directly

The SDK keeps the same host and port configuration story as transcription.

## Open Questions Deferred

- richer realtime synthesis chunking guarantees
- additional output formats beyond `wav`
- structured error objects instead of Phase 1 string errors
- remote runtime discovery and Tailscale-aware routing
