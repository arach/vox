# VOX-001: Browser Live Session Contract

Status: Draft
Date: 2026-04-16
Owners: Vox bridge and runtime
Reviewed with: Hudson (`codex` harness via Scout)

## Summary

VOX-001 defines the Phase 1 contract for browser live sessions over the local HTTP bridge.

The immediate goal is to freeze the browser-to-bridge-to-daemon surface before Vox grows an always-on voice processor or multi-app Hudson integration. The proposal keeps the current bridge shape recognizable, but makes five areas explicit:

- session identity and ownership
- busy semantics
- `stop` vs `cancel`
- disconnect and reattach behavior
- partial and error payload shapes

This proposal also keeps warm-up separate from live session control and treats always-on capture as a future primitive, not an overload of the current live session API.

## Context

Vox already has the pieces for browser live sessions:

- the daemon exposes `transcribe.startSession`, `transcribe.sessionStatus`, `transcribe.stopSession`, and `transcribe.cancelSession`
- the local HTTP bridge now proxies those routes as `/live`, `/live/stop`, and `/live/cancel`
- `@voxd/client` now exposes a browser live-session API backed by an NDJSON stream
- capabilities now report `features.realtime`

That baseline is enough to ship an end-to-end path, but it does not yet freeze the public contract strongly enough for Hudson or other multi-surface browser integrations.

## Goals

- Define a stable browser live-session contract for Phase 1.
- Preserve `clientId`, `route`, and `modelId` as first-class telemetry dimensions.
- Make single-session concurrency behavior explicit.
- Freeze terminal semantics for `stop`, `cancel`, timeout, and disconnect.
- Freeze stream payload shapes for state, partial, final, and error events.
- Leave room for future protocol evolution without breaking the first browser integrations.

## Non-Goals

- Always-on voice processing.
- Background hotword or ambient capture.
- Multi-session mixing or parallel microphone capture.
- Moving warm-up behind live-session start.
- Solving browser auth beyond the existing local-origin allowlist story.

## Proposal

### 1. Version the bridge surface now

Phase 1 should introduce versioned bridge routes and keep the current unversioned routes as compatibility aliases during rollout.

Primary routes:

- `GET /v1/capabilities`
- `GET /v1/live`
- `POST /v1/live`
- `POST /v1/live/stop`
- `POST /v1/live/cancel`

Compatibility aliases during rollout:

- `GET /capabilities`
- `GET /live`
- `POST /live`
- `POST /live/stop`
- `POST /live/cancel`

The bridge should report the live-session protocol version in capabilities:

```json
{
  "features": {
    "realtime": true
  },
  "realtime": {
    "protocolVersion": 1,
    "liveSessions": true,
    "partials": false,
    "reattach": false,
    "alwaysOn": false
  }
}
```

Rationale:

- browser integrations need a stable contract boundary
- future always-on and richer partials should not force a breaking reinterpretation of `/live`
- a simple boolean `features.realtime` remains useful for feature detection, while the `realtime` object carries the contract details

### 2. Separate telemetry identity from app identity

`clientId` remains required and remains the primary telemetry dimension.

Phase 1 should add an optional `originAppId` field for browser live sessions:

```ts
interface LiveSessionOwner {
  clientId: string;
  originAppId?: string;
}
```

Rules:

- `clientId` identifies the product surface that should own telemetry, for example `hudson-voice`, `vox-browser`, or `browser-extension`
- `originAppId` identifies the higher-level app or canvas that initiated the live session, for example `hudson.canvas.main`
- Vox must not overload `route` to encode app identity
- if `originAppId` is absent, Vox still works, but Hudson-class integrations should provide it

This keeps telemetry stable while avoiding the long-term trap of a flat `clientId` in multi-app browser contexts.

### 3. Freeze the concurrency policy

Phase 1 remains single-session:

- only one live session may own the microphone at a time
- the active session has one `sessionOwner`
- `GET /v1/live` returns the active session if one exists
- `POST /v1/live` returns a typed busy error if another session is active

Busy responses should be explicit:

```json
{
  "error": {
    "code": "live_session_busy",
    "message": "Another live session already owns the microphone.",
    "sessionOwner": {
      "sessionId": "session_123",
      "clientId": "hudson-voice",
      "originAppId": "hudson.canvas.main",
      "state": "recording",
      "startedAt": "2026-04-16T13:04:11Z"
    }
  }
}
```

Recommended HTTP status:

- `409 Conflict` for `live_session_busy`

This is intentionally stronger than a plain string error because browser clients need to know who currently owns the session before they decide whether to wait, render a busy UI, or ask for handoff.

### 4. Freeze lifecycle semantics

The Phase 1 live-session state machine is:

- `starting`
- `recording`
- `processing`
- `done`
- `cancelled`
- `error`

The allowed transitions are:

- `starting -> recording`
- `recording -> processing`
- `recording -> cancelled`
- `recording -> error`
- `processing -> done`
- `processing -> error`

`GET /v1/live` should return:

```ts
interface LiveSessionStatus {
  sessionId: string;
  connectionId: string;
  clientId: string;
  originAppId?: string;
  modelId: string;
  startedAt: string;
  state: SessionState;
}
```

`connectionId` remains useful for daemon ownership and debugging, but browser clients should treat `sessionId` as the stable cross-request handle.

### 5. Make `stop` and `cancel` materially different

`stop` and `cancel` should not be interchangeable.

Control-plane requests should carry explicit owner identity:

```ts
interface LiveSessionControlRequest {
  sessionId: string;
  clientId: string;
  originAppId?: string;
}
```

The bridge must reject `stop` or `cancel` when the caller identity does not match the active `sessionOwner`.

`POST /v1/live/stop` means:

- stop microphone capture immediately
- release the microphone before transcription begins
- preserve recorded audio
- transition the session to `processing`
- eventually emit a final transcript

`POST /v1/live/cancel` means:

- stop microphone capture immediately
- release the microphone immediately
- discard recorded audio
- transition the session to `cancelled`
- do not emit a final transcript

Control responses should acknowledge control-plane acceptance, not wait for the final transcript:

```json
{
  "accepted": true,
  "sessionId": "session_123",
  "state": "processing"
}
```

Recommended statuses:

- `200 OK` for accepted `stop`
- `200 OK` for accepted `cancel`
- `404 Not Found` for `live_session_not_found`
- `409 Conflict` for `live_session_owner_mismatch`

The final transcript continues to arrive on the live-session stream opened by `POST /v1/live`.

### 6. Phase 1 does not support reattach

If the streaming HTTP connection that opened the live session goes away, the runtime should cancel the session.

Phase 1 rules:

- live sessions are not reattachable
- bridge disconnect cancels the active session
- connection-close cancellation must release the microphone
- `GET /v1/live` may briefly show the session while cancellation is in flight, but it must converge to `null`

Capabilities must advertise this explicitly:

```json
{
  "realtime": {
    "reattach": false
  }
}
```

This avoids implicit semantics where a browser client assumes it can reconnect to an orphaned session later.

### 7. Freeze the stream envelope now

The live stream should continue using NDJSON. Each line is one JSON object.

Envelope:

```ts
type LiveStreamEnvelope =
  | { event: "session.state"; data: SessionStateEvent }
  | { event: "session.partial"; data: LiveSessionPartialEvent }
  | { event: "session.final"; data: SessionFinalEvent }
  | { event: "session.error"; data: LiveSessionErrorEvent }
  | { result: SessionFinalEvent | SessionCancelledResult };
```

Payloads:

```ts
interface SessionStateEvent {
  sessionId: string;
  state: SessionState;
  previous?: SessionState | null;
  reason?: string;
}

interface LiveSessionPartialEvent {
  sessionId: string;
  sequence: number;
  text: string;
  isFinal: false;
}

interface SessionFinalEvent {
  sessionId: string;
  text: string;
  durationMs: number;
  words?: AlignedWord[];
  metrics?: {
    inferenceMs: number;
    totalMs: number;
    realtimeFactor: number;
  };
}

interface SessionCancelledResult {
  sessionId: string;
  cancelled: true;
  reason?: string;
}

interface LiveSessionErrorEvent {
  sessionId?: string;
  code: LiveSessionErrorCode;
  message: string;
  retryable: boolean;
}
```

Rules:

- `session.final` and the terminal `result` payload must be semantically equivalent on success
- `session.partial` is optional in Phase 1 and may not appear for backends that only produce final transcripts
- when partials are supported later, `sequence` must be monotonic per session
- the bridge may coalesce or drop intermediate partials under backpressure, but it must preserve ordering and it must never drop `session.state`, `session.final`, or `session.error`

### 8. Freeze a small error taxonomy

Phase 1 should stop treating live-session failures as opaque strings.

```ts
type LiveSessionErrorCode =
  | "live_session_busy"
  | "live_session_not_found"
  | "live_session_owner_mismatch"
  | "session_cancelled"
  | "recording_timeout"
  | "connection_closed"
  | "microphone_unavailable"
  | "transcription_failed"
  | "daemon_unavailable"
  | "origin_not_allowed"
  | "protocol_error";
```

Rules:

- HTTP responses return structured `error` payloads with `code` and `message`
- streaming failures emit `session.error`
- terminal cancellation uses `session_cancelled` plus a machine-readable `reason` when applicable
- `recording_timeout` and `connection_closed` must stay distinguishable because they imply different UI and retry behavior

### 9. Keep warm-up separate from live control

Warm-up remains a separate public capability:

- `warmup.status`
- `warmup.start`
- `warmup.schedule`

Live-session start may opportunistically trigger warm-up under the hood, but the browser live-session contract must not redefine warm-up or hide it from clients.

This matters for Hudson because intent-driven warm-up should stay independently observable even when a later session never actually starts recording.

### 10. Always-on is a future primitive

VOX-001 deliberately does not define always-on voice processing.

If Vox later adds an ambient or always-on processor, it should be a separate surface with its own capability bit and lifecycle, for example:

- `realtime.alwaysOn = true`
- `/v2/ambient`
- `processor.start`
- `processor.stop`

It should not reuse the current `/live` semantics because:

- ownership is different
- mic lifetime is different
- transcript delivery is different
- Hudson will likely need buffering, intent routing, and background policy that do not belong in Phase 1 live sessions

## Implementation Review

This section reviews the current implementation in the tree against the proposal.

### Already aligned

- The bridge already exposes browser live-session endpoints in [swift/Sources/VoxBridge/HTTPBridgeServer.swift](/Users/arach/dev/vox/swift/Sources/VoxBridge/HTTPBridgeServer.swift).
- The daemon already exposes start, status, stop, and cancel session routes in [swift/Sources/VoxService/VoxRuntimeService.swift](/Users/arach/dev/vox/swift/Sources/VoxService/VoxRuntimeService.swift).
- The bridge already streams NDJSON envelopes via [swift/Sources/VoxBridge/HTTPBridgeCodec.swift](/Users/arach/dev/vox/swift/Sources/VoxBridge/HTTPBridgeCodec.swift).
- The browser client already parses the NDJSON live stream in [packages/web-client/src/client.ts](/Users/arach/dev/vox/packages/web-client/src/client.ts).
- Capabilities already expose `features.realtime`.
- Disconnect currently cancels the active session in the daemon, which matches the proposed non-reattachable Phase 1 stance.
- There is already an end-to-end browser-to-bridge-to-daemon test in [packages/web-client/test/live-session.e2e.test.ts](/Users/arach/dev/vox/packages/web-client/test/live-session.e2e.test.ts).

### Gaps to close

- Routes are still unversioned. The bridge needs `/v1/*` aliases and the browser client should prefer them.
- `features.realtime` is currently only a boolean. The richer `realtime` capability object does not exist yet.
- Live-session ownership is still just `clientId`; `originAppId` is not yet present in the bridge, browser client, or daemon status payloads.
- Busy errors are still plain strings, so callers cannot inspect the active `sessionOwner`.
- `stop` currently behaves like a long-running terminal RPC and returns after transcription completes. The proposal changes that to immediate acknowledgement plus final result on the stream.
- `stop` and `cancel` do not currently enforce explicit owner metadata at the bridge boundary.
- The stream shape does not yet expose `session.error` as a structured event.
- Partial transcript payloads are typed in the browser client but are not emitted by the daemon yet.

## Rollout Order

The implementation order after this proposal should be:

1. Add versioned `/v1/live*` and `/v1/capabilities` routes while preserving current aliases.
2. Add structured capability metadata for realtime.
3. Add `originAppId` and structured `sessionOwner` payloads.
4. Convert busy and terminal errors to typed error payloads.
5. Change `stop` to acknowledge on mic release and keep the final transcript on the original stream.
6. Add structured `session.error` events and freeze the browser client error parsing around them.
7. Decide whether Phase 1 ships without partials or with best-effort coalesced partials, but keep the payload shape fixed either way.

## Decision

Adopt VOX-001 as the Phase 1 browser live-session contract, then make the bridge and browser client conform to it before adding any always-on voice processor surface.
