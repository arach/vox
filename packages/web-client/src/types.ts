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
  type: "alignment";
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
  /** Companion bridge port. Default: 43115 */
  port?: number;
  /** Probe timeout in ms. Default: 2000 */
  probeTimeout?: number;
  /** Polling interval in ms when waiting for a job. Default: 500 */
  pollInterval?: number;
}
