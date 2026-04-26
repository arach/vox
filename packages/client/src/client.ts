import { RuntimeDiscovery } from "./discovery.ts";
import { DEFAULT_HOST, STREAM_TIMEOUT_MS } from "./constants.ts";
import { parseAnnotationMetrics, parseSynthesisMetrics, parseTranscriptionMetrics } from "./metrics.ts";
import { WebSocketTransport } from "./transport.ts";
import { VoxLiveSession } from "./live.ts";
import { parseAttributedWordTimings, parseSpeakerSegments } from "./annotation.ts";
import { parseWordTimings } from "./words.ts";
import type {
  DoctorReport,
  FileAnnotationResult,
  FileTranscriptionResult,
  LiveSessionStatus,
  ModelInfo,
  ModelProgress,
  SynthesisOptions,
  SynthesisResult,
  VoiceInfo,
  WarmupStatus,
  VoxClientOptions,
} from "./types.ts";

export class VoxClient {
  private readonly discovery = new RuntimeDiscovery();
  private readonly transport = new WebSocketTransport();
  private readonly clientId: string;
  private resolvedPort: number | null = null;

  constructor(private readonly options: VoxClientOptions = {}) {
    this.clientId = options.clientId ?? "vox-client";
  }

  get connected(): boolean {
    return this.transport.isConnected;
  }

  async connect(): Promise<void> {
    this.resolvedPort = this.discovery.resolvePort(this.options.port);
    const host = this.options.host ?? DEFAULT_HOST;
    await this.transport.connect(this.resolvedPort, host);
  }

  disconnect(): void {
    this.transport.disconnect();
  }

  async call(
    method: string,
    params?: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    return this.transport.call(method, { clientId: this.clientId, ...params });
  }

  async callStreaming(
    method: string,
    params: Record<string, unknown> | undefined,
    onProgress: (event: string, data: Record<string, unknown>) => void,
  ): Promise<Record<string, unknown>> {
    return this.transport.callStreaming(
      method,
      { clientId: this.clientId, ...params },
      onProgress,
    );
  }

  async health(): Promise<Record<string, unknown>> {
    return this.call("health");
  }

  async doctor(): Promise<DoctorReport> {
    const result = await this.call("doctor.run");
    return {
      ready: Boolean(result.ready),
      checks: (result.checks as DoctorReport["checks"]) ?? [],
    };
  }

  async listModels(): Promise<ModelInfo[]> {
    const result = await this.call("models.list");
    return (result.models as ModelInfo[]) ?? [];
  }

  async listVoices(modelId?: string): Promise<VoiceInfo[]> {
    const result = await this.call("synthesize.voices", modelId ? { modelId } : undefined);
    return (result.voices as VoiceInfo[]) ?? [];
  }

  async installModel(
    modelId = "parakeet:v3",
    onProgress?: (event: ModelProgress) => void,
  ): Promise<ModelInfo> {
    const result = await this.callStreaming("models.install", { modelId }, (event, data) => {
      if (event === "models.progress" && onProgress) {
        onProgress({
          modelId: String(data.modelId ?? modelId),
          progress: Number(data.progress ?? 0),
          status: String(data.status ?? ""),
        });
      }
    });
    return result.model as ModelInfo;
  }

  async preloadModel(
    modelId = "parakeet:v3",
    onProgress?: (event: ModelProgress) => void,
  ): Promise<ModelInfo> {
    const result = await this.callStreaming("models.preload", { modelId }, (event, data) => {
      if (event === "models.progress" && onProgress) {
        onProgress({
          modelId: String(data.modelId ?? modelId),
          progress: Number(data.progress ?? 0),
          status: String(data.status ?? ""),
        });
      }
    });
    return result.model as ModelInfo;
  }

  async getWarmupStatus(modelId = "parakeet:v3"): Promise<WarmupStatus> {
    const result = await this.call("warmup.status", { modelId });
    return result.warmup as WarmupStatus;
  }

  async startWarmup(modelId = "parakeet:v3"): Promise<WarmupStatus> {
    const result = await this.call("warmup.start", { modelId });
    return result.warmup as WarmupStatus;
  }

  async scheduleWarmup(modelId = "parakeet:v3", delayMs = 0): Promise<WarmupStatus> {
    const result = await this.call("warmup.schedule", { modelId, delayMs });
    return result.warmup as WarmupStatus;
  }

  async transcribeFile(path: string, modelId = "parakeet:v3"): Promise<FileTranscriptionResult> {
    const result = await this.transport.call(
      "transcribe.file",
      { clientId: this.clientId, path, modelId },
      STREAM_TIMEOUT_MS,
    );
    return {
      modelId: String(result.modelId ?? modelId),
      text: String(result.text ?? ""),
      elapsedMs: Number(result.elapsedMs ?? 0),
      metrics: parseTranscriptionMetrics(result.metrics, Number(result.elapsedMs ?? 0)),
      words: parseWordTimings(result.words),
    };
  }

  async annotateFile(
    path: string,
    options: {
      modelId?: string;
      text?: string;
      words?: Array<{
        word: string;
        start: number;
        end: number;
        confidence: number;
      }>;
    } = {},
  ): Promise<FileAnnotationResult> {
    const modelId = options.modelId ?? "speaker-diarization:v1";
    const result = await this.transport.call(
      "annotate.file",
      {
        clientId: this.clientId,
        path,
        modelId,
        text: options.text,
        words: options.words,
      },
      STREAM_TIMEOUT_MS,
    );

    return {
      modelId: String(result.modelId ?? modelId),
      text: typeof result.text === "string" ? result.text : undefined,
      elapsedMs: Number(result.elapsedMs ?? 0),
      metrics: parseAnnotationMetrics(result.metrics, Number(result.elapsedMs ?? 0)),
      words: parseAttributedWordTimings(result.words),
      speakers: parseSpeakerSegments(result.speakers),
    };
  }

  async synthesize(text: string, options: SynthesisOptions = {}): Promise<SynthesisResult> {
    const result = await this.transport.call(
      "synthesize.generate",
      {
        clientId: this.clientId,
        text,
        modelId: options.modelId ?? "avspeech:system",
        voiceId: options.voiceId,
        format: options.format ?? "wav",
        speed: options.speed,
        instructions: options.instructions,
      },
      STREAM_TIMEOUT_MS,
    );

    const audioBase64 = String(result.audioBase64 ?? "");
    const audio = Buffer.from(audioBase64, "base64");
    return {
      modelId: String(result.modelId ?? options.modelId ?? "avspeech:system"),
      voiceId: String(result.voiceId ?? options.voiceId ?? ""),
      format: String(result.format ?? options.format ?? "wav"),
      contentType: String(result.contentType ?? "audio/wav"),
      audio: new Uint8Array(audio),
      audioBytes: Number(result.audioBytes ?? audio.length),
      elapsedMs: Number(result.elapsedMs ?? 0),
      metrics: parseSynthesisMetrics(result.metrics, Number(result.elapsedMs ?? 0)),
    };
  }

  async getLiveSessionStatus(): Promise<LiveSessionStatus | null> {
    const result = await this.call("transcribe.sessionStatus");
    const raw = result.session;
    if (!raw || typeof raw !== "object") {
      return null;
    }

    const session = raw as Record<string, unknown>;
    return {
      sessionId: String(session.sessionId ?? ""),
      connectionId: String(session.connectionId ?? ""),
      clientId: String(session.clientId ?? ""),
      modelId: String(session.modelId ?? ""),
      startedAt: String(session.startedAt ?? ""),
      state: String(session.state ?? "error") as LiveSessionStatus["state"],
    };
  }

  async cancelLiveSession(sessionId?: string): Promise<{ cancelled: boolean; sessionId: string }> {
    const result = await this.call("transcribe.cancelSession", sessionId ? { sessionId } : undefined);
    return {
      cancelled: Boolean(result.cancelled),
      sessionId: String(result.sessionId ?? sessionId ?? ""),
    };
  }

  createLiveSession(): VoxLiveSession {
    return new VoxLiveSession(this);
  }
}
