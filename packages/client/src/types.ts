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
  host?: string;
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

export interface VoiceInfo {
  id: string;
  name: string;
  language?: string | null;
  backend: string;
  modelId: string;
  available: boolean;
  default: boolean;
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

export interface SpeakerSegment {
  speakerId: string;
  start: number;
  end: number;
  confidence?: number | null;
}

export interface AttributedWordTiming {
  word: string;
  start: number;
  end: number;
  confidence: number;
  speakerId?: string | null;
}

export interface FileTranscriptionResult {
  modelId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
}

export interface AnnotationMetrics {
  traceId: string;
  audioDurationMs: number;
  inputBytes: number;
  wasPreloaded: boolean;
  fileCheckMs: number;
  modelCheckMs: number;
  modelLoadMs: number;
  audioLoadMs: number;
  audioPrepareMs: number;
  diarizationMs: number;
  totalMs: number;
  realtimeFactor: number;
}

export interface FileAnnotationResult {
  modelId: string;
  text?: string;
  elapsedMs: number;
  metrics?: AnnotationMetrics;
  words: AttributedWordTiming[];
  speakers: SpeakerSegment[];
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

export interface SynthesisOptions {
  modelId?: string;
  voiceId?: string;
  format?: string;
  speed?: number;
  instructions?: string;
  credentials?: {
    OPENAI_API_KEY?: string;
    openaiApiKey?: string;
    openai_api_key?: string;
  };
}

export interface SynthesisMetrics {
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

export interface SynthesisResult {
  modelId: string;
  voiceId: string;
  format: string;
  contentType: string;
  audio: Uint8Array;
  audioBytes: number;
  elapsedMs: number;
  metrics?: SynthesisMetrics;
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

export interface LiveSessionStatus {
  sessionId: string;
  connectionId: string;
  clientId: string;
  modelId: string;
  startedAt: string;
  state: SessionState;
}

export interface SessionFinalEvent {
  sessionId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  words: WordTiming[];
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
