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
export interface RealtimeOptions {
  /** Audio format. Default: "pcm16" */
  format?: "pcm16" | "wav";
  /** Sample rate in Hz. Default: 16000 */
  sampleRate?: number;
  /** Language code. Default: "en" */
  language?: string;
}

/** Events emitted by a realtime transcription session. */
export interface RealtimeSession {
  /** Send an audio chunk to the runtime. */
  send(chunk: ArrayBuffer): void;
  /** Signal end of audio input. */
  stop(): void;
  /** Register a callback for partial transcriptions. */
  onPartial(cb: (text: string) => void): void;
  /** Register a callback for the final transcription. */
  onFinal(cb: (result: TranscriptionResult) => void): void;
  /** Register a callback for errors. */
  onError(cb: (error: Error) => void): void;
  /** Close the session. */
  close(): void;
}
