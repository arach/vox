# Live Session Recovery and Transcript History API Design

Status: draft, reviewed via Scout with Claude and revised
Scope: Vox Companion runtime, TypeScript SDKs, browser HTTP bridge, CLI/TUI, and Vox macOS app surfaces

## Problem

Live transcription currently assumes the streaming client remains present until the session is stopped and finalized. That creates three user-visible failures:

1. **Client reload loses control.** A web/dev client can disappear while `voxd` is still recording. The new client can query/cancel status, but it cannot reattach to the old event stream or recover the final transcript.
2. **No daemon-owned transcript history.** The TUI has a local `~/.vox/voice.jsonl` history, but Companion does not persist successful live/file transcripts as a shared runtime capability. The macOS app keeps only the latest check transcript in memory.
3. **Silent 120s recording cap.** `LiveSessionCoordinator.maxRecordingSeconds` is hard-coded to 120 seconds and currently auto-cancels instead of finalizing. The cap is not visible in API status, client UI, or preferences.

The fix should preserve Vox's design principles: explicit runtime surfaces, observable lifecycle, client identity in telemetry, and root-cause recovery over client-side workaround.

## Goals

- Make live ASR sessions recoverable across client reloads and transport drops.
- Allow a reloaded client to inspect, attach to, stop, cancel, or fetch the result of an existing session.
- Persist final transcript records in a daemon-owned history store usable by the app, CLI, TUI, SDK, and web client.
- Preserve `clientId`, `route`, `modelId`, metrics, and word timings in both telemetry and history.
- Replace the invisible 120s cancel with a configurable, visible recording limit whose default behavior preserves a transcript when possible.
- Keep existing `transcribe.startSession`, `transcribe.stopSession`, `transcribe.cancelSession`, and `transcribe.sessionStatus` compatible for current clients.

## Non-goals

- True streaming ASR partial text from the provider. This design is about session ownership/recovery around the current record-then-transcribe flow.
- Persisting raw microphone audio by default. History stores transcript metadata and word timings, not audio bytes.
- Multi-recording concurrency. Vox can keep a single active mic recording until the recorder/runtime is intentionally redesigned for multiple inputs.

## Model

A live session is split into three concepts:

- **Session ownership:** who may stop/cancel/attach. The original `connectionID` proves ownership only while that exact connection is alive. Any cross-connection recovery action requires an opaque `sessionToken`; `clientId` remains telemetry/UX metadata, not an auth boundary.
- **Event attachments:** one or more active streams subscribed to the session lifecycle. Attachments can come and go without destroying the session.
- **Durable result:** once a session reaches `done`, `cancelled`, or `error`, the terminal state and final transcript/error are retained long enough for reload recovery and, for successful transcripts, are appended to history.

### Session lifecycle

```text
starting -> recording -> processing -> done
          \            \-> error
           \-> cancelled
```

Disconnect no longer implies cancellation for recoverable sessions. Instead, the session stays active and `attachedCount` drops. Orphan handling is explicit via policy and timers.

## RPC API

### 1. Enhanced `transcribe.startSession`

Existing streaming route remains supported. It now creates a recoverable session by default for companion/browser clients and emits an early `session.started` event with the recovery envelope.

Request:

```ts
interface TranscribeStartSessionParams {
  clientId?: string;
  modelId?: string;

  /** Default: "recoverable" for HTTP/browser bridge, "cancelOnDisconnect" for legacy direct clients until SDKs opt in. */
  recoveryMode?: "recoverable" | "cancelOnDisconnect";

  /** Default: runtime preference. Null is accepted only when runtime policy allows unbounded direct-local recording. */
  recordingLimitMs?: number | null;

  /** What to do when recordingLimitMs is reached. Default: "stopAndTranscribe". */
  limitAction?: "stopAndTranscribe" | "cancel";

  /** What to do when no attachment remains. Default comes from runtime policy; recoverable/browser sessions use "stopAndTranscribe". */
  orphanAction?: "continue" | "stopAndTranscribe" | "cancel";

  /** Applies when orphanAction is not immediate. Recoverable/browser sessions default to a finite timeout. */
  orphanTimeoutMs?: number | null;

  /** Optional product metadata; must be redacted before persistence. */
  metadata?: Record<string, unknown>;
}
```

New streaming events:

```ts
interface SessionStartedEvent {
  sessionId: string;
  sessionToken?: string;
  clientId: string;
  modelId: string;
  state: "starting" | "recording";
  startedAt: string;
  recoveryMode: "recoverable" | "cancelOnDisconnect";
  recordingLimitMs: number | null;
  recordingDeadlineAt?: string;
  orphanAction: "continue" | "stopAndTranscribe" | "cancel";
  orphanTimeoutMs: number | null;
}
```

Compatibility:

- Existing clients that only listen for `session.state` and wait for the final result continue to work.
- Existing `stopSession` still finalizes the active session.
- Existing `cancelSession` still cancels the active session.

### 2. New `transcribe.createSession`

Non-streaming route for clients that want explicit session handles before attaching to events.

```ts
// RPC
transcribe.createSession(params: TranscribeStartSessionParams): Promise<LiveSessionEnvelope>
```

Response:

```ts
interface LiveSessionEnvelope {
  sessionId: string;
  sessionToken?: string;
  clientId: string;
  modelId: string;
  state: SessionState;
  startedAt: string;
  updatedAt: string;
  recoveryMode: "recoverable" | "cancelOnDisconnect";
  recordingLimitMs: number | null;
  recordingDeadlineAt?: string;
  orphanAction: "continue" | "stopAndTranscribe" | "cancel";
  orphanTimeoutMs: number | null;
  attachedCount: number;
  owner: {
    clientId: string;
    originAppId?: string;
  };
}
```

### 3. New `transcribe.attachSession`

Streaming route that subscribes to an existing session. It replays the latest state immediately, then streams future state/final events. If the session is already terminal, it returns/replays the terminal result immediately.

```ts
interface TranscribeAttachSessionParams {
  sessionId: string;
  clientId?: string;
  sessionToken?: string;
  replay?: "state" | "all"; // default: "state"
}
```

Authorization rule:

- Same connection: the live `connectionID` that created the session may stop/cancel/attach without a token.
- Cross-connection recovery: `sessionToken` is required for attach, stop, cancel, and result fetch. This includes browser reloads and second local clients.
- `clientId` is not proof of ownership; any caller can claim it today, so it is only telemetry and UX attribution.
- `sessionToken` is server-generated, at least 128 bits of entropy, bound to `sessionId` plus bridge origin when applicable, rotated on successful cross-connection attach, and cleared on terminal state.
- Browser SDKs should store the token in `sessionStorage` by default, not `localStorage`; apps that opt into persistent storage must accept the XSS/exfiltration tradeoff.
- Mismatches return structured `live_session_owner_mismatch` payloads, not plain strings.

### 4. Enhanced `transcribe.sessionStatus`

Current route remains, but status becomes recovery-aware.

```ts
interface LiveSessionStatusResponse {
  session: LiveSessionStatus | null;
}

interface LiveSessionStatus {
  sessionId: string;
  connectionId?: string;
  clientId: string;
  modelId: string;
  startedAt: string;
  updatedAt: string;
  state: SessionState;
  recoveryMode: "recoverable" | "cancelOnDisconnect";
  recoverable: boolean;
  attachedCount: number;
  recordingLimitMs: number | null;
  recordingDeadlineAt?: string;
  elapsedRecordingMs?: number;
  orphanedAt?: string;
  orphanAction?: "continue" | "stopAndTranscribe" | "cancel";
  orphanDeadlineAt?: string;
  resultAvailable: boolean;
  historyId?: string;
  error?: LiveSessionErrorPayload;
}
```

### 5. Enhanced `transcribe.stopSession`

Stop remains non-streaming and may be called by a reloaded client. When processing completes, the result is persisted in session memory and history. The response may include the transcript so a non-attached recovery client can recover immediately.

```ts
interface StopSessionParams {
  sessionId?: string;
  clientId?: string;
  sessionToken?: string;
}

interface StopSessionResponse {
  stopped: true;
  sessionId: string;
  result?: SessionFinalEvent;
  historyId?: string;
}
```

For compatibility, direct callers may still receive `{ stopped: true, sessionId }` while the original streaming `startSession` resolves with the final transcript. New SDKs should prefer returning the final result from `stop()`.

### 6. New `transcribe.sessionResult`

Fetch a terminal session result after reload or after `stopSession` has processed.

```ts
interface SessionResultParams {
  sessionId: string;
  clientId?: string;
  sessionToken?: string;
}

interface SessionResultResponse {
  sessionId: string;
  state: SessionState;
  result?: SessionFinalEvent;
  historyId?: string;
  error?: LiveSessionErrorPayload;
}
```

### 7. Enhanced `transcribe.cancelSession`

Cancel requires ownership checks and returns structured error payloads on mismatch/not found.

```ts
interface CancelSessionParams {
  sessionId?: string;
  clientId?: string;
  sessionToken?: string;
  reason?: string;
}
```

## Transcript history API

Terminal transcript results use this shape:

```ts
interface SessionFinalEvent {
  sessionId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}
```

History is daemon-owned and should use a new dedicated versioned JSONL file, proposed as `~/.vox/history.jsonl` via a new `RuntimePaths.historyLogURL()`. Do **not** append the new daemon schema into the current `~/.vox/voice.jsonl`: that file is currently TUI/CLI-owned and has a different ad hoc schema. Migrate the TUI to read daemon history rather than leaving it as a separate source of truth.

### Record schema

```ts
type SpeechHistoryKind = "transcription" | "synthesis";
type TranscriptionSource = "file" | "live";

type SpeechHistoryRecord = TranscriptionHistoryRecord | SynthesisHistoryRecord;

interface TranscriptionHistoryRecord {
  schemaVersion: 1;
  id: string;
  kind: "transcription";
  source: TranscriptionSource;
  route: "transcribe.file" | "transcribe.live";
  sessionId?: string;
  requestId?: string;
  clientId: string;
  originAppId?: string;
  modelId: string;
  text: string;
  textLength: number;
  words: WordTiming[];
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  outcome: "ok" | "error" | "cancelled";
  error?: string;
  startedAt?: string;
  completedAt: string;
  metadata?: Record<string, string | number | boolean>;
}

interface SynthesisHistoryRecord {
  schemaVersion: 1;
  id: string;
  kind: "synthesis";
  route: "synthesize.generate" | "synthesize.startSession";
  sessionId?: string;
  clientId: string;
  modelId: string;
  voiceId?: string;
  textLength: number;
  elapsedMs: number;
  metrics?: SynthesisMetrics;
  outcome: "ok" | "error" | "cancelled";
  completedAt: string;
}
```

Persistence rules:

- Write successful `transcribe.file` and live `transcribe.stopSession`/timeout-finalized transcripts.
- Do not store raw audio by default.
- Do not store provider credentials or unredacted arbitrary metadata.
- Recording-limit expiry should produce an `ok` history record when transcription succeeds, not a cancellation record.
- Error/cancel records may be retained as lightweight audit entries if useful for UX, but clients can filter them out by default.

### RPC routes

Use top-level `history.*` routes so history can cover transcription and synthesis without inventing a broader `speech.*` namespace.

```ts
history.list(params?: {
  kind?: "transcription" | "synthesis";
  source?: "file" | "live";
  clientId?: string;
  modelId?: string;
  sessionId?: string;
  outcome?: "ok" | "error" | "cancelled";
  limit?: number;        // default 50, max 500
  before?: string;       // completedAt cursor or record id cursor
  query?: string;        // optional text contains/search, best-effort
}): Promise<{ records: SpeechHistoryRecord[]; nextCursor?: string }>;

history.get({ id: string }): Promise<{ record: SpeechHistoryRecord | null }>;

history.delete({ id: string }): Promise<{ deleted: boolean; id: string }>;

history.clear(params?: {
  kind?: "transcription" | "synthesis";
  clientId?: string;
  before?: string;
}): Promise<{ deleted: number }>;
```

## Browser HTTP bridge API

Add HTTP equivalents for web reload recovery:

- `GET /live` -> enhanced status.
- `POST /live` -> existing streaming start, emits `session.started`.
- `POST /live/create` -> `transcribe.createSession`.
- `GET /live/:sessionId/attach?token=...` -> NDJSON event stream from `transcribe.attachSession`.
- `POST /live/stop` -> enhanced stop, accepts `{ sessionId, sessionToken }`.
- `GET /live/:sessionId/result?token=...` -> terminal result.
- `GET /history?...` -> `history.list`.
- `GET /history/:id` -> `history.get`.
- `DELETE /history/:id` -> `history.delete`.

The bridge must detect broken HTTP streams and detach the attachment. It must not leave a `DaemonProxy.callStreaming` request alive solely because the downstream browser connection disappeared.

## SDK API

### `@voxd/sdk`

```ts
class VoxClient {
  createLiveSession(options?: LiveSessionOptions): VoxLiveSession;
  createRecoverableLiveSession(options?: LiveSessionOptions): Promise<VoxLiveSession>;
  attachLiveSession(sessionId: string, options?: AttachLiveSessionOptions): VoxLiveSession;
  getLiveSessionStatus(): Promise<LiveSessionStatus | null>;
  getLiveSessionResult(sessionId: string, options?: SessionAuthOptions): Promise<SessionResultResponse>;

  listHistory(options?: HistoryListOptions): Promise<HistoryListResult>;
  getHistoryRecord(id: string): Promise<SpeechHistoryRecord | null>;
  deleteHistoryRecord(id: string): Promise<boolean>;
}

interface LiveSessionOptions {
  modelId?: string;
  recoveryMode?: "recoverable" | "cancelOnDisconnect";
  recordingLimitMs?: number | null;
  limitAction?: "stopAndTranscribe" | "cancel";
  orphanAction?: "continue" | "stopAndTranscribe" | "cancel";
  orphanTimeoutMs?: number | null;
}

class VoxLiveSession {
  readonly id: string | null;
  readonly token: string | null;
  start(options?: LiveSessionOptions): Promise<SessionFinalEvent>;
  attach(options?: AttachLiveSessionOptions): Promise<SessionFinalEvent>;
  stop(): Promise<SessionFinalEvent | void>;
  cancel(reason?: string): Promise<void>;
}
```

### `@voxd/client` browser SDK

Browser reload pattern:

```ts
const client = createVoxdClient({ clientId: "my-dev-app" });
const status = await client.getLiveSessionStatus();

if (status?.recoverable && status.clientId === client.clientId) {
  const session = client.attachLiveSession(status.sessionId, {
    sessionToken: sessionStorage.getItem(`vox.session.${status.sessionId}`) ?? undefined,
  });
  session.onFinal(saveTranscript);
  // The user can now stop/cancel or wait for final.
}
```

On `session.started`, browser SDK stores the session token in memory plus optional caller-provided storage hook. Tokens should be short-lived and removed on terminal state.

## Timeout and safety policy

Replace hard-coded cancellation with named runtime preferences:

```ts
interface LiveSessionRuntimePolicy {
  defaultRecordingLimitMs: number;         // proposed default: 600_000 (10 minutes)
  maxRecordingLimitMs: number;             // proposed safety ceiling: 3_600_000 (60 minutes)
  defaultLimitAction: "stopAndTranscribe" | "cancel";
  defaultOrphanAction: "continue" | "stopAndTranscribe" | "cancel";
  defaultOrphanTimeoutMs: number | null;   // proposed default: 60_000 for recoverable browser sessions
}
```

Recommended defaults:

- `defaultRecordingLimitMs = 600_000` (10 minutes), not 120 seconds.
- `maxRecordingLimitMs = 3_600_000` (60 minutes) unless an operator explicitly raises it. Record-then-transcribe should not allow unbounded in-memory audio by default.
- `defaultLimitAction = "stopAndTranscribe"` so an automatic limit preserves the transcript.
- For recoverable/browser sessions, `defaultOrphanAction = "stopAndTranscribe"` and `defaultOrphanTimeoutMs = 60_000`; a closed tab should not hold the only mic session forever.
- Indefinite `continue` is reserved for intentional direct-local clients that visibly own the mic and can still be manually stopped/cancelled.

Every status response should expose `recordingLimitMs`, `recordingDeadlineAt`, and `orphanDeadlineAt` so clients can show timers instead of surprising the user.

## Error payloads

Move live routes from plain error strings toward `LiveSessionErrorPayload` dictionaries. Keep string compatibility in the bridge until SDKs parse structured errors.

```ts
interface LiveSessionErrorPayload {
  code:
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
  message: string;
  sessionOwner?: LiveSessionStatus;
  reason?: string;
  retryable?: boolean;
}
```

## Implementation plan

1. **History recorder first**
   - Add a `SpeechHistoryRecorder` in `VoxCore`/`VoxService` around a new `RuntimePaths.historyLogURL()`.
   - Append records for `transcribe.file` and successful live session finalization. Reconcile with `performance.jsonl`: history should either reference the performance sample id/trace id or be the source used to project user-facing history, so telemetry and transcript history do not diverge.
   - Add `history.*` RPC routes and CLI `vox history` / `vox logs history` parity.
   - Update TUI and macOS app to read daemon history instead of only local/in-memory state.

2. **Recoverable session state**
   - Extend `LiveSessionCoordinator.Session` with token, recovery policy, attached count, terminal result, history id, timestamps, and deadlines.
   - Decouple recoverable `Session` lifetime from `connectionID`; replace immediate disconnect cancellation with detach/orphan policy. The existing streaming reply callback must be detachable without cancelling the session; after detach, `stopSession` and `sessionResult` become the recovery result path.
   - Add `transcribe.createSession`, `transcribe.attachSession`, and `transcribe.sessionResult`.
   - Enhance `sessionStatus`, `stopSession`, and `cancelSession` responses.

3. **Bridge and SDK recovery**
   - Teach `HTTPBridgeServer` to detach upstream streaming calls when downstream HTTP streams break.
   - Add browser SDK token storage hook and reload attach helper.
   - Add TS SDK attach/result/history methods.

4. **Timeout/preferences UX**
   - Replace `maxRecordingSeconds = 120` with runtime policy loaded from preferences/env.
   - Change timeout action default from cancel to stop-and-transcribe.
   - Surface active countdown/status in app/TUI/browser clients.

5. **Tests**
   - Coordinator tests for disconnect-detach, orphan timeout, recording-limit stop-and-transcribe, owner mismatch, and terminal result retention.
   - Bridge tests for browser stream break detaches without leaking upstream calls or cancelling recoverable sessions.
   - SDK tests for attach after reload and history parsing.

## Compatibility notes

- Old SDKs can keep using `transcribe.startSession` as a single long-lived streaming request.
- The current `vox transcribe status` and `vox transcribe cancel` commands continue to work with richer output.
- New clients should prefer recoverable mode and explicit attach/result APIs.
- The hard-coded 120s cap should not be removed without a visible finite replacement policy; safety remains explicit.
