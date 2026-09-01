---
title: "VOX-003: Spoken Output and Runtime Events"
description: Draft contract for coherent spoken output, cue timing, and pushed runtime state.
---

Status: Draft
Date: 2026-05-13
Owners: Vox runtime, bridge, SDK, and OpenScout voice integrations
Reviewed with: OpenScout via Scout

## Summary

VOX-003 defines the next contract boundary for spoken output and runtime state updates.

The immediate problem is that user-level spoken workflows, such as an OpenScout Ranger brief, were too easy to model as many small text-to-speech calls or as a long-running TTS live session. Both shapes are wrong for the common case.

Default rule:

- one user-level spoken response should normally produce one `synthesize.generate` request
- product-level UI steps should be cues over that audio, not separate synthesis jobs
- live ASR keeps its session model because it owns microphone capture
- ordinary TTS should stay unary unless Vox can provide real output streaming or playback progress
- TTS generation is asynchronous and may run concurrently; Vox must not impose a global TTS mutex
- runtime state should be pushed to clients through subscriptions, not discovered through high-frequency status polling

This document extends VOX-001 and VOX-002 without replacing them.

## Context

VOX-001 defines browser live ASR sessions: microphone ownership, `stop` vs `cancel`, disconnect cleanup, and typed busy/status semantics.

VOX-002 defines synthesis: `synthesize.generate` for unary speech output and `synthesize.startSession` for longer-running output flows.

Recent OpenScout Ranger testing exposed three gaps:

- a single brief can become many independent TTS calls if UI steps are treated as speech boundaries
- OpenAI TTS latency and network errors become more likely when one spoken response is split across several provider requests
- Vox app and bridge clients currently lean on frequent `sessionStatus` polling because there is no durable runtime event stream

The root cause is a missing product/runtime boundary. OpenScout should own product structure and UI cues. Vox should own speech generation, provider lifecycle, warm-up, cancellation, and telemetry.

## Goals

- Model spoken responses as first-class utterances.
- Keep `synthesize.generate` as the default TTS path for normal spoken output.
- Preserve `clientId`, `route`, `modelId`, and `voiceId` telemetry dimensions.
- Give OpenScout a way to correlate one spoken response with one Vox synthesis trace.
- Define cue metadata without requiring providers to support word timings.
- Replace hot `sessionStatus` polling with a push-first runtime event model.
- Keep polling routes as recovery and operator diagnostics.
- Leave room for real streaming TTS without pretending current chunked audio is realtime playback progress.

## Non-Goals

- Replacing VOX-001 live ASR semantics.
- Adding realtime speech-to-speech.
- Making Vox own browser playback, OpenScout visual navigation, or Apple app product policy. Optional `VoxAppleSpeech` is reusable Apple playback machinery, not that product policy.
- Requiring OpenAI or any TTS provider to return speech marks in Phase 1.
- Removing `synthesize.startSession`.
- Turning event delivery into speech performance telemetry.

## Spoken Output Contract

### Concurrency

TTS requests are independent asynchronous work items.

OpenScout or another client may submit many `synthesize.generate` requests in parallel and await the results independently. Vox should preserve request identity and telemetry for each call. Vox should not decide playback order by serializing provider execution.

If a provider or local resource has a real capacity limit, that limit must be explicit. Vox can reject, queue, or backpressure at a provider/model/channel boundary, but it must not silently collapse all TTS into one process-wide lane.

For API-backed TTS providers, the default assumption is concurrent HTTP requests are allowed. Rate limits and retry policy belong to provider-specific capacity/backpressure handling.

### Optional Speech Timing

One-shot TTS may optionally request `speechTiming`.

The first implementation uses a post-synthesis forced-alignment pass when the TTS provider does not return native speech marks. That flow is:

1. synthesize one coherent audio artifact
2. feed the generated audio back through ASR
3. collect word timings from ASR
4. map recognized words back to the original synthesis text
5. return approximate word and cue timings with the synthesis result

This is opt-in because it adds work and may require an ASR model to be available. It should be useful for UI surfaces such as Ranger where one coherent spoken response needs cue timing for visual navigation.

Request shape:

```json
{
  "method": "synthesize.generate",
  "params": {
    "clientId": "openscout-web",
    "originAppId": "openscout.ranger",
    "utteranceId": "brief_123",
    "text": "Full spoken response text.",
    "modelId": "gpt-4o-mini-tts",
    "voiceId": "alloy",
    "format": "wav",
    "speechTiming": {
      "enabled": true,
      "modelId": "parakeet:v3",
      "cues": [
        {
          "id": "step_1",
          "textStart": 0,
          "textEnd": 120
        },
        {
          "id": "step_2",
          "text": "Second cue text from the same generated utterance."
        }
      ]
    }
  }
}
```

Response extension:

```json
{
  "modelId": "gpt-4o-mini-tts",
  "voiceId": "alloy",
  "format": "wav",
  "contentType": "audio/wav",
  "audioBase64": "<base64 wav bytes>",
  "audioBytes": 48244,
  "elapsedMs": 142,
  "metrics": {
    "traceId": "ab12cd34",
    "synthesisMs": 121,
    "totalMs": 142,
    "audioDurationMs": 820
  },
  "speechTiming": {
    "source": "asr",
    "modelId": "parakeet:v3",
    "elapsedMs": 180,
    "words": [
      {
        "word": "Full",
        "startMs": 0,
        "endMs": 180,
        "confidence": 0.99,
        "sourceTextStart": 0,
        "sourceTextEnd": 4
      }
    ],
    "cues": [
      {
        "id": "step_1",
        "startMs": 0,
        "endMs": 420,
        "confidence": 0.92,
        "source": "asr"
      }
    ]
  }
}
```

Speech timing rules:

- speech timing is best-effort and must not change generated audio
- synthesis success should not fail just because speech timing fails unless the caller opts into a future strict mode
- speech timing elapsed time must stay separate from TTS synthesis metrics
- ASR model load/warm-up cost must remain visible
- cue timings may be estimated from nearest matched words when exact text spans do not align cleanly
- clients should treat cue confidence as advisory
- Vox accepts the draft `alignment` request key as a compatibility alias, but emits `speechTiming` in responses

### User-level utterance

A user-level utterance is the speech artifact a user experiences as one assistant turn.

Examples:

- one Ranger brief
- one assistant reply
- one reminder announcement
- one "say that again" replay

For these cases, OpenScout should produce one normalized text body and call:

- `synthesize.generate`

OpenScout should not split a brief into one TTS request per visual step unless a provider limit forces chunking.

### Cue metadata

OpenScout may keep structured cues for UI synchronization:

```ts
type SpokenResponse = {
  responseId: string;
  source: "ranger.brief" | "ranger.reply" | "reminder";
  text: string;
  cues?: Array<{
    id: string;
    label: string;
    route?: Record<string, unknown>;
    textStart?: number;
    textEnd?: number;
    estimatedOffsetMs?: number;
  }>;
};
```

Cues are not synthesis boundaries. They are product metadata over one spoken response.

Phase 1 cue offsets may be estimated from text ranges, word counts, and returned `audioDurationMs`. If a provider later returns word timings or speech marks, those can refine the same cue model.

### Vox synthesis request

The existing VOX-002 request remains valid:

```json
{
  "method": "synthesize.generate",
  "params": {
    "clientId": "openscout-web",
    "text": "Full spoken response text.",
    "modelId": "gpt-4o-mini-tts",
    "voiceId": "alloy",
    "format": "wav",
    "speed": 1.0
  }
}
```

A future compatible extension may include opaque product metadata:

```json
{
  "method": "synthesize.generate",
  "params": {
    "clientId": "openscout-web",
    "originAppId": "openscout.ranger",
    "utteranceId": "brief_123",
    "text": "Full spoken response text.",
    "modelId": "gpt-4o-mini-tts",
    "voiceId": "alloy",
    "format": "wav",
    "cues": [
      {
        "id": "step_1",
        "textStart": 0,
        "textEnd": 82,
        "estimatedOffsetMs": 0
      }
    ]
  }
}
```

Vox may ignore unknown metadata until the field is explicitly adopted in SDK types.

### Playback

Playback is a caller-owned audible-surface concern, not a `TTSProvider` concern. Generation concurrency is not playback concurrency. Clients may generate or prefetch multiple utterances in parallel, but each audible surface should have a playback arbiter.

Vox does not make browser playback and Apple playback the same product.

- Browser and OpenScout apps own their playback policy when they receive audio from `/api/voice/speak` or `@voxd/client`. Reply replacement, ducking, cue timing, and queue priority stay in that product.
- Apple embed apps may play `SynthesisOutput.audioData` themselves, or opt into the reusable `VoxAppleSpeech` controller for one audible surface. That controller is playback machinery: live `AVSpeechSynthesizer.speak()` for `avspeech:system`, generated-audio sinks for byte-producing models, replace/stop/cancel, and typed phase events. It is not OpenScout policy, Ranger cue policy, or app-level reply dedupe.

`TTSProvider` and `TTSEngineManager` remain generation-only. Do not add `speak()` to the provider surface to approximate Apple playback.

OpenScout owns browser playback when it receives audio from `/api/voice/speak` or `@voxd/client`.

OpenScout should:

- decode the returned audio
- play through its chosen HTMLAudio or WebAudio path
- keep only one primary spoken response audible per surface by default
- stop, duck, replace, or queue existing speech when a new higher-priority utterance starts
- track actual playback time
- advance UI cues from playback time
- stop playback immediately on user cancel

Examples:

- Ranger brief playback should replace or cancel a stale Ranger brief.
- A short confirmation can interrupt or duck a long narration only if the product explicitly wants that priority.
- Parallel prefetch is fine; overlapping audible speech should be opt-in, not the default.

OpenScout should not use `synthesize.startSession` only to approximate progress. That route should be reserved for flows where Vox can provide meaningful streaming output or session lifecycle semantics.

### Cancellation

One user stop action should cancel both phases:

- pending generation
- active playback

For pending `synthesize.generate`, cancellation should close or abort the in-flight request path:

1. browser aborts `/api/voice/speak`
2. OpenScout server closes or aborts its Vox RPC request
3. Vox cancels the in-flight generation task for that connection

For active playback, OpenScout stops local playback immediately.

`synthesize.cancel` remains scoped to `synthesize.startSession`.

### Provider-limit chunking

If a provider requires chunking, chunking should be explicit fallback behavior.

Rules:

- preserve one OpenScout `responseId`
- preserve one user-facing playback sequence
- aggregate provider chunks into one spoken response in OpenScout logs
- record Vox performance per provider request, but correlate all chunks to the parent response
- avoid using chunk boundaries as UI cue boundaries unless no better timing is available

## Telemetry and Observability

Vox performance telemetry remains speech-work telemetry.

For `synthesize.generate`, Vox records:

- `clientId`
- `route`
- `modelId`
- `voiceId`
- `outcome`
- `textLength`
- `metrics.traceId`
- `metrics.synthesisMs`
- `metrics.totalMs`
- `metrics.audioDurationMs`
- `metrics.outputBytes`

OpenScout should preserve enough metadata to correlate:

- `responseId` or `briefId`
- Vox `traceId`
- model and voice
- playback start/end/cancel
- cue timing, if relevant

Diagnostics must be route-aware:

- ASR routes show `infer=`
- TTS routes show `synth=`
- `total=` always means wall-clock request or session duration

Runtime event delivery must not be written to `performance.jsonl` as speech performance.

## Runtime Event Contract

### Problem

`transcribe.sessionStatus` and `synthesize.sessionStatus` are snapshot routes. They are useful for diagnostics, recovery, and operator inspection.

They are not a good primary live update channel. Polling `sessionStatus` every few hundred milliseconds creates unnecessary bridge load, noisy logs, and poor semantics: clients repeatedly ask for state that the runtime already mutates internally.

### Proposal

Add one canonical Vox runtime event model with two transports:

- daemon WebSocket: `runtime.subscribe`
- HTTP bridge: `GET /events`

Keep slow polling as fallback.

### Daemon WebSocket route

Request:

```json
{
  "id": "1",
  "method": "runtime.subscribe",
  "params": {
    "clientId": "openscout-web",
    "topics": [
      "health",
      "warmup",
      "transcribe.session",
      "synthesize.session",
      "jobs"
    ],
    "since": 0
  }
}
```

Initial response:

```json
{
  "id": "1",
  "result": {
    "subscriptionId": "sub_123",
    "seq": 42,
    "snapshot": {
      "warmup": [],
      "transcribeSession": null,
      "synthesisSession": null
    }
  }
}
```

Event frame:

```json
{
  "event": "runtime.event",
  "data": {
    "seq": 43,
    "timestamp": "2026-05-13T16:31:00Z",
    "topic": "transcribe.session",
    "type": "session.state",
    "clientId": "openscout-web",
    "route": "transcribe.live",
    "modelId": "parakeet:v3",
    "sessionId": "session_123",
    "state": "recording"
  }
}
```

### HTTP bridge route

Request:

```http
GET /events?clientId=openscout-web&topics=warmup,transcribe.session,jobs&since=42
```

Response:

- content type: `application/x-ndjson`
- each line uses the same `{ "event": "...", "data": ... }` envelope as the daemon WebSocket

### Topics

Initial topics:

- `health`
- `warmup`
- `transcribe.session`
- `synthesize.session`
- `jobs`

Future topics may include:

- `provider`
- `performance`
- `logs`

`performance` and `logs` events are operational notifications. They do not replace the performance log or daemon log files.

### Reconnect and replay

Runtime events use at-least-once delivery with monotonic `seq`.

Rules:

- every event has `seq`, `timestamp`, `topic`, and `type`
- subscribe returns a snapshot plus the current `seq`
- reconnect sends `since`
- if replay buffer contains `since + 1`, Vox replays missed events
- if replay is unavailable, Vox returns `snapshotRequired: true`
- clients then fetch the relevant snapshot routes once
- HTTP event streams emit heartbeat events every 15-30 seconds
- clients reconnect with exponential backoff and jitter

### Backpressure

Vox should log subscriber backpressure operationally, not in performance telemetry.

Recommended counters:

- active WebSocket subscribers
- active HTTP event streams
- events emitted by topic
- replay buffer depth
- dropped event count
- slow-poll fallback count

## Implementation Plan

### Vox runtime

1. Add a runtime event broadcaster behind `VoxRuntimeService`.
2. Emit events on warm-up, live ASR state/final/cancel, synthesis session state/final/cancel, and job state changes.
3. Add `runtime.subscribe`.
4. Keep `transcribe.sessionStatus` and `synthesize.sessionStatus` as snapshot routes.

### Vox bridge

1. Extend `ServiceBridge` with connection-scoped subscribers.
2. Allow id-less daemon event frames for runtime events.
3. Teach `DaemonProxy` to forward id-less events instead of dropping them.
4. Add HTTP `GET /events` as chunked NDJSON.
5. Suppress routine status route logs; log subscription lifecycle and replay behavior instead.

### SDKs

1. Expose `client.subscribeRuntime()` or `client.onRuntimeEvent()` in `@voxd/sdk`.
2. Make `@voxd/client` prefer `/events` for job/session state.
3. Keep existing polling as fallback when events are unavailable.

### Vox app

1. Replace the hot session polling loop with runtime subscription.
2. Use slow snapshot polling only when disconnected, after resume, or when diagnostics asks for a manual refresh.
3. Fix diagnostics metric labels so ASR and TTS timings are not conflated.

### OpenScout

1. Keep one `synthesize.generate` call per Ranger brief.
2. Make cue advancement playback-time driven.
3. Return Vox metrics and trace IDs through `/api/voice/speak`.
4. Propagate browser abort to server-side Vox RPC cancellation.
5. Add feature identity such as `originAppId: "openscout.ranger"` when Vox supports it.
6. Use optional synthesis `speechTiming` for Ranger cue timing when latency overhead is acceptable.

## Migration

Phase 1:

- keep current `synthesize.generate` request shape
- keep one TTS call per Ranger brief
- expose metrics through OpenScout
- reduce status polling and suppress routine status logs
- fix diagnostics labels

Phase 2:

- add Vox `runtime.subscribe`
- add HTTP `/events`
- update SDKs and Vox app to consume events
- keep polling fallback

Phase 3:

- add typed cue metadata if needed
- add `originAppId` to synthesis requests
- add optional `speechTiming` using post-synthesis ASR/forced alignment for word and cue timings
- consider real provider speech marks when available
- revisit `synthesize.startSession` only when Vox can provide meaningful streaming/progress semantics

## Open Questions

- Should `originAppId` be accepted on all runtime routes or only bridge/browser-facing routes?
- Should one-shot `synthesize.generate` cancellation get an explicit request-id cancel route, or is connection/request abort enough?
- Should cue metadata live in Vox request params, OpenScout-only response metadata, or both?
- Should `speechTiming` remain part of `synthesize.generate`, or should Vox later add a separate helper over an existing audio artifact?
- Should speech timing failure stay silent best-effort by default with a strict mode for tests/tools?
- How large should the event replay buffer be?
- Should HTTP `/events` be versioned immediately as `/v1/events` with an unversioned compatibility alias?

## Bottom Line

The root-cause fix is to align the protocol with the product shape:

- ASR live sessions are for microphone ownership.
- TTS generation is normally one coherent utterance.
- UI steps are cues, not TTS jobs.
- Runtime state is pushed, not polled every few hundred milliseconds.

Confirm shipped behavior against the [Runtime Guide](./runtime.md), SDK types, and current service implementation.
