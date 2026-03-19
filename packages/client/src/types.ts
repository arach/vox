export interface RuntimeInfo {
  version: string;
  serviceName: string;
  port: number;
  pid: number;
  startedAt: string;
}

export interface RpcRequest {
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export interface RpcResponse {
  id?: string;
  result?: Record<string, unknown>;
  error?: string;
}

export interface RpcEvent {
  id?: string;
  event: string;
  data?: Record<string, unknown>;
}

export type WireMessage = RpcResponse | RpcEvent;

export interface VoxClientOptions {
  clientId?: string;
  port?: number;
}

export interface DoctorCheck {
  name: string;
  status: "ok" | "warning" | "error";
  detail: string;
}

export interface DoctorReport {
  ready: boolean;
  checks: DoctorCheck[];
}

export interface ModelInfo {
  id: string;
  name: string;
  backend: string;
  installed: boolean;
  preloaded: boolean;
  available: boolean;
}

export interface ModelProgress {
  modelId: string;
  progress: number;
  status: string;
}

export interface WarmupStatus {
  modelId: string;
  state: "idle" | "scheduled" | "warming" | "ready" | "failed";
  requestedBy?: string | null;
  scheduledFor?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
  lastError?: string | null;
}

export interface WordTiming {
  word: string;
  start: number;   // seconds
  end: number;      // seconds
  confidence: number;
}

export interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}

export interface TranscriptionMetrics {
  traceId: string;
  audioDurationMs: number;
  inputBytes: number;
  wasPreloaded: boolean;
  fileCheckMs: number;
  modelCheckMs: number;
  modelLoadMs: number;
  audioLoadMs: number;
  audioPrepareMs: number;
  inferenceMs: number;
  totalMs: number;
  realtimeFactor: number;
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
}

export interface SessionFinalEvent {
  sessionId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
}

export interface LiveSessionEvents {
  state: SessionStateEvent;
  partial: { sessionId: string; text: string };
  final: SessionFinalEvent;
  error: { error: Error };
}

export interface TransportEvents {
  open: undefined;
  close: { code: number; reason: string };
  event: { event: string; data: Record<string, unknown> };
  error: { error: Error };
}
