/** Health check response from the companion. */
export interface VoxHealth {
  ok: boolean;
  service: string;
  version: string;
  port: number;
}

/** Companion capability report. */
export interface VoxCapabilities {
  running: boolean;
  version: string;
  features: {
    alignment?: boolean;
    local_asr?: boolean;
    streaming_progress?: boolean;
    realtime?: boolean;
  };
  backends: {
    parakeet?: boolean;
    mlx?: boolean;
    ane?: boolean;
  };
  daemon?: Record<string, unknown>;
  models?: unknown[];
}

/** Audio source for an alignment job. */
export interface JobSource {
  audioUrl: string;
  format?: "mp3" | "wav" | "aac" | "opus";
}

/** Metadata attached to a job for downstream use. */
export interface JobMetadata {
  documentId?: string;
  pageNumber?: number;
  paragraphId?: string;
  [key: string]: unknown;
}

/** Options for creating an alignment job. */
export interface CreateJobOptions {
  type: "alignment" | "transcription";
  sessionId?: string;
  source: JobSource;
  metadata?: JobMetadata;
}

/** Accepted job response. */
export interface JobAccepted {
  jobId: string;
  accepted: boolean;
}

/** Job status stages. */
export type JobStage =
  | "accepted"
  | "fetching_audio"
  | "preparing"
  | "transcribing"
  | "aligning"
  | "finalizing"
  | "processing"
  | "completed"
  | "failed";

/** Word-level alignment timing. */
export interface AlignedWord {
  word: string;
  start: number;
  end: number;
}

/** Alignment result payload. */
export interface AlignmentResult {
  words: AlignedWord[];
  text?: string;
  durationMs: number;
}

/** Full job status response. */
export interface JobStatus {
  jobId: string;
  type: string;
  status: JobStage;
  result?: {
    alignment?: AlignmentResult;
    transcription?: TranscriptionResult;
  };
  error?: string;
}

/** Companion connection state. */
export type CompanionState =
  | "unknown"
  | "probing"
  | "connected"
  | "unavailable";

/** Options for the VoxD client. */
export interface VoxDClientOptions {
  /** Stable client identity for telemetry. Default: "vox-web" */
  clientId?: string;
  /** Base URL for the companion bridge. Default: http://127.0.0.1:43115 */
  baseUrl?: string;
  /** Companion bridge port. Ignored if baseUrl is set. Default: 43115 */
  port?: number;
  /** Probe timeout in ms. Default: 2000 */
  probeTimeout?: number;
  /** Polling interval in ms when waiting for a job. Default: 500 */
  pollInterval?: number;
}

/** Options for transcribe(). */
export interface TranscribeOptions {
  /** Audio data — a Blob, File, or ArrayBuffer. */
  audio: Blob | File | ArrayBuffer;
  /** Audio format hint. Default: inferred from Blob type or "wav". */
  format?: "mp3" | "wav" | "aac" | "opus" | "pcm16";
  /** Language code. Default: "en" */
  language?: string;
  /** Request word-level timestamps. Default: false */
  timestamps?: boolean;
  /** Optional metadata for the job. */
  metadata?: JobMetadata;
}

/** Transcription result. */
export interface TranscriptionResult {
  text: string;
  durationMs: number;
  words?: AlignedWord[];
  metrics?: {
    inferenceMs: number;
    totalMs: number;
    realtimeFactor: number;
  };
}

/** Options for starting a realtime transcription stream. */
export interface LiveSessionOptions {
  /** Model to use for the live session. Default: "parakeet:v3" */
  modelId?: string;
}

export type SessionState =
  | "starting"
  | "recording"
  | "processing"
  | "done"
  | "cancelled"
  | "error";

export interface SessionStateEvent {
  sessionId: string;
  state: SessionState;
  previous?: SessionState | null;
  reason?: string;
}

export interface LiveSessionStatus {
  sessionId: string;
  connectionId: string;
  clientId: string;
  modelId: string;
  startedAt: string;
  state: SessionState;
}

export interface LiveSessionPartialEvent {
  sessionId: string;
  text: string;
}

export interface SessionFinalEvent extends TranscriptionResult {
  sessionId: string;
}

/** Events emitted by a live transcription session. */
export interface LiveSession {
  /** Current session id once the bridge reports it. */
  readonly id: string | null;
  /** Start the session and wait for the final transcript. */
  start(options?: LiveSessionOptions): Promise<SessionFinalEvent>;
  /** Stop the active recording and finalize transcription. */
  stop(): Promise<void>;
  /** Cancel the active recording without a transcript result. */
  cancel(): Promise<void>;
  /** Register a callback for session state changes. */
  onState(cb: (event: SessionStateEvent) => void): () => void;
  /** Register a callback for partial transcriptions. */
  onPartial(cb: (event: LiveSessionPartialEvent) => void): () => void;
  /** Register a callback for the final transcription. */
  onFinal(cb: (event: SessionFinalEvent) => void): () => void;
  /** Register a callback for errors. */
  onError(cb: (error: Error) => void): () => void;
  /** Cancel the session without awaiting the result. */
  close(): void;
}

export type RealtimeOptions = LiveSessionOptions;
export type RealtimeSession = LiveSession;
