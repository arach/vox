import { RuntimeDiscovery } from "./discovery.ts";
import { STREAM_TIMEOUT_MS } from "./constants.ts";
import { parseTranscriptionMetrics } from "./metrics.ts";
import { WebSocketTransport } from "./transport.ts";
import { VoxLiveSession } from "./live.ts";
import type {
  DoctorReport,
  FileTranscriptionResult,
  ModelInfo,
  ModelProgress,
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
    await this.transport.connect(this.resolvedPort);
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
    };
  }

  createLiveSession(): VoxLiveSession {
    return new VoxLiveSession(this);
  }
}
