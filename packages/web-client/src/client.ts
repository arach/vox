import type {
  AlignmentResult,
  CompanionState,
  CreateJobOptions,
  JobAccepted,
  JobStatus,
  LiveSession,
  LiveSessionOptions,
  LiveSessionPartialEvent,
  LiveSessionStatus,
  SessionFinalEvent,
  SessionStateEvent,
  TranscribeOptions,
  TranscriptionResult,
  VoxCapabilities,
  VoxDClientOptions,
  VoxHealth,
} from "./types.js";
import {
  DEFAULT_HOST,
  DEFAULT_POLL_INTERVAL,
  DEFAULT_PORT,
  DEFAULT_PROBE_TIMEOUT,
} from "./constants.js";

/**
 * Create a VoxD client instance.
 *
 * @example
 * ```ts
 * import { createVoxdClient } from "@voxd/client";
 *
 * const client = createVoxdClient();
 *
 * if (await client.probe()) {
 *   const result = await client.transcribe({
 *     audio: audioBlob,
 *     language: "en",
 *     timestamps: true,
 *   });
 *   console.log(result.text);
 *   console.log(result.words);
 * }
 * ```
 */
export function createVoxdClient(options?: VoxDClientOptions): VoxDClient {
  return new VoxDClient(options);
}

/**
 * Browser client for the Vox Companion local transcription runtime.
 *
 * Supports:
 * - Sending recorded audio (Blob/File/ArrayBuffer) for transcription
 * - Getting word-level timestamps for alignment
 * - Checking companion capabilities
 * - Probing companion availability
 *
 * Does NOT handle:
 * - Microphone selection or browser permissions
 * - MediaDevices API or getUserMedia
 * - Raw audio capture
 */
export class VoxDClient {
  private readonly base: string;
  private readonly clientId: string;
  private readonly probeTimeout: number;
  private readonly pollInterval: number;
  private _state: CompanionState = "unknown";

  constructor(options?: VoxDClientOptions) {
    if (options?.baseUrl) {
      this.base = options.baseUrl.replace(/\/$/, "");
    } else {
      const host = options?.host ?? DEFAULT_HOST;
      const port = options?.port ?? DEFAULT_PORT;
      this.base = `http://${host}:${port}`;
    }
    this.clientId = options?.clientId ?? "vox-web";
    this.probeTimeout = options?.probeTimeout ?? DEFAULT_PROBE_TIMEOUT;
    this.pollInterval = options?.pollInterval ?? DEFAULT_POLL_INTERVAL;
  }

  /** Current connection state. */
  get state(): CompanionState {
    return this._state;
  }

  /** Whether the companion is connected and responding. */
  get isConnected(): boolean {
    return this._state === "connected";
  }

  // ── Discovery ────────────────────────────────────────────

  /**
   * Probe the companion. Returns true if reachable.
   * Safe to call on every page load — fails fast and silently.
   */
  async probe(): Promise<boolean> {
    this._state = "probing";
    try {
      const res = await this.fetch("/health", { timeout: this.probeTimeout });
      const data: VoxHealth = await res.json();
      this._state = data.ok ? "connected" : "unavailable";
      return data.ok;
    } catch {
      this._state = "unavailable";
      return false;
    }
  }

  /** Fetch the health status. Throws if companion is unreachable. */
  async health(): Promise<VoxHealth> {
    const res = await this.fetch("/health");
    return res.json();
  }

  /** Fetch capabilities — features, backends, models. */
  async capabilities(): Promise<VoxCapabilities> {
    const res = await this.fetch("/capabilities");
    return res.json();
  }

  // ── Transcription ──────────────────────────────────────

  /**
   * Transcribe audio from a Blob, File, or ArrayBuffer.
   *
   * This uploads the audio to the local companion and returns
   * the transcription result. Optionally includes word-level
   * timestamps for playback alignment.
   *
   * @example
   * ```ts
   * const result = await client.transcribe({
   *   audio: blob,
   *   language: "en",
   *   timestamps: true,
   * });
   * console.log(result.text);
   * console.log(result.words); // word-level timestamps
   * ```
   */
  async transcribe(options: TranscribeOptions): Promise<TranscriptionResult> {
    const { audio, format, language, timestamps, metadata } = options;

    // Build multipart form
    const form = new FormData();

    if (audio instanceof Blob) {
      const ext = format ?? inferFormat(audio.type) ?? "wav";
      form.append("audio", audio, `audio.${ext}`);
    } else {
      // ArrayBuffer — wrap in Blob
      const ext = format ?? "wav";
      const blob = new Blob([audio], { type: mimeForFormat(ext) });
      form.append("audio", blob, `audio.${ext}`);
    }

    if (format) form.append("format", format);
    if (language) form.append("language", language);
    if (timestamps) form.append("timestamps", "true");
    form.append("metadata", JSON.stringify(this.withClientMetadata(metadata)));

    const res = await this.fetch("/transcribe", {
      method: "POST",
      body: form,
    });

    return res.json();
  }

  // ── Alignment (URL-based) ──────────────────────────────

  /**
   * Create a job on the companion.
   * Returns the accepted job with its ID.
   */
  async createJob(options: CreateJobOptions): Promise<JobAccepted> {
    const res = await this.fetch("/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...options,
        metadata: this.withClientMetadata(options.metadata),
      }),
    });
    return res.json();
  }

  /** Poll a job's status by ID. */
  async getJob(jobId: string): Promise<JobStatus> {
    const res = await this.fetch(`/jobs/${jobId}`);
    return res.json();
  }

  /**
   * Submit an alignment job (via audio URL) and wait for the result.
   *
   * Use `transcribe()` instead if you have the audio data locally.
   * This method is for when the companion should fetch audio from a URL.
   */
  async align(
    options: Omit<CreateJobOptions, "type">,
  ): Promise<AlignmentResult> {
    const { jobId } = await this.createJob({ ...options, type: "alignment" });
    return this.waitForJob(jobId);
  }

  // ── Live Sessions ──────────────────────────────────────

  createLiveSession(): LiveSession {
    return new VoxDLiveSession(
      (options) => this.openLiveSession(options),
      (sessionId) => this.stopLiveSession(sessionId),
      (sessionId) => this.cancelLiveSession(sessionId),
    );
  }

  async getLiveSessionStatus(): Promise<LiveSessionStatus | null> {
    const res = await this.fetch("/live");
    const payload = await res.json() as { session?: Record<string, unknown> | null };
    const raw = payload.session;
    if (!raw || typeof raw !== "object") {
      return null;
    }

    return {
      sessionId: String(raw.sessionId ?? ""),
      connectionId: String(raw.connectionId ?? ""),
      clientId: String(raw.clientId ?? ""),
      modelId: String(raw.modelId ?? ""),
      startedAt: String(raw.startedAt ?? ""),
      state: String(raw.state ?? "error") as LiveSessionStatus["state"],
    };
  }

  async stopLiveSession(sessionId?: string): Promise<{ stopped: boolean; sessionId: string }> {
    const res = await this.fetch("/live/stop", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sessionId ? { sessionId } : {}),
    });
    const payload = await res.json() as Record<string, unknown>;
    return {
      stopped: Boolean(payload.stopped),
      sessionId: String(payload.sessionId ?? sessionId ?? ""),
    };
  }

  async cancelLiveSession(sessionId?: string): Promise<{ cancelled: boolean; sessionId: string }> {
    const res = await this.fetch("/live/cancel", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sessionId ? { sessionId } : {}),
    });
    const payload = await res.json() as Record<string, unknown>;
    return {
      cancelled: Boolean(payload.cancelled),
      sessionId: String(payload.sessionId ?? sessionId ?? ""),
    };
  }

  // ── Deep links ───────────────────────────────────────────

  /**
   * Attempt to launch the companion via deep link.
   * Useful when `probe()` returns false.
   */
  launch(): void {
    window.location.href = "vox://launch";
  }

  /** Open the companion settings window. */
  openSettings(): void {
    window.location.href = "vox://settings";
  }

  // ── Internals ────────────────────────────────────────────

  private async waitForJob(jobId: string): Promise<AlignmentResult> {
    const maxAttempts = 600; // 5 minutes at 500ms
    for (let i = 0; i < maxAttempts; i++) {
      const status = await this.getJob(jobId);

      if (status.status === "completed") {
        if (!status.result?.alignment) {
          throw new VoxDError("Job completed but no alignment result", "no_result");
        }
        return status.result.alignment;
      }

      if (status.status === "failed") {
        throw new VoxDError(
          status.error ?? "Job failed",
          "job_failed",
        );
      }

      await sleep(this.pollInterval);
    }

    throw new VoxDError("Job timed out", "timeout");
  }

  private async openLiveSession(options?: LiveSessionOptions): Promise<Response> {
    return this.fetch("/live", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        clientId: this.clientId,
        modelId: options?.modelId ?? "parakeet:v3",
      }),
    });
  }

  private withClientMetadata<T extends Record<string, unknown> | undefined>(metadata: T): Record<string, unknown> {
    const base: Record<string, unknown> = metadata ? { ...metadata } : {};
    if (base.clientId == null && base.surface == null) {
      base.clientId = this.clientId;
    }
    return base;
  }

  private async fetch(
    path: string,
    init?: RequestInit & { timeout?: number },
  ): Promise<Response> {
    const { timeout, ...fetchInit } = init ?? {};

    const controller = new AbortController();
    const timer = timeout
      ? setTimeout(() => controller.abort(), timeout)
      : undefined;

    try {
      const res = await globalThis.fetch(`${this.base}${path}`, {
        ...fetchInit,
        signal: controller.signal,
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        throw new VoxDError(
          `${res.status} ${res.statusText}: ${body}`,
          "http_error",
        );
      }

      return res;
    } catch (err) {
      if (err instanceof VoxDError) throw err;
      throw new VoxDError(
        err instanceof Error ? err.message : "Companion unreachable",
        "network_error",
      );
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}

/** Error thrown by the VoxD client. */
export class VoxDError extends Error {
  constructor(
    message: string,
    public readonly code:
      | "network_error"
      | "http_error"
      | "live_session_error"
      | "job_failed"
      | "no_result"
      | "protocol_error"
      | "session_cancelled"
      | "timeout",
  ) {
    super(message);
    this.name = "VoxDError";
  }
}

class VoxDLiveSession implements LiveSession {
  private sessionId: string | null = null;
  private runPromise: Promise<SessionFinalEvent> | null = null;
  private finalEvent: SessionFinalEvent | null = null;
  private readonly stateListeners = new Set<(event: SessionStateEvent) => void>();
  private readonly partialListeners = new Set<(event: LiveSessionPartialEvent) => void>();
  private readonly finalListeners = new Set<(event: SessionFinalEvent) => void>();
  private readonly errorListeners = new Set<(error: Error) => void>();

  constructor(
    private readonly open: (options?: LiveSessionOptions) => Promise<Response>,
    private readonly stopRequest: (sessionId?: string) => Promise<unknown>,
    private readonly cancelRequest: (sessionId?: string) => Promise<unknown>,
  ) {}

  get id(): string | null {
    return this.sessionId;
  }

  start(options?: LiveSessionOptions): Promise<SessionFinalEvent> {
    if (!this.runPromise) {
      this.runPromise = this.run(options);
    }
    return this.runPromise;
  }

  async stop(): Promise<void> {
    await this.stopRequest(this.sessionId ?? undefined);
  }

  async cancel(): Promise<void> {
    await this.cancelRequest(this.sessionId ?? undefined);
  }

  onState(cb: (event: SessionStateEvent) => void): () => void {
    this.stateListeners.add(cb);
    return () => this.stateListeners.delete(cb);
  }

  onPartial(cb: (event: LiveSessionPartialEvent) => void): () => void {
    this.partialListeners.add(cb);
    return () => this.partialListeners.delete(cb);
  }

  onFinal(cb: (event: SessionFinalEvent) => void): () => void {
    this.finalListeners.add(cb);
    return () => this.finalListeners.delete(cb);
  }

  onError(cb: (error: Error) => void): () => void {
    this.errorListeners.add(cb);
    return () => this.errorListeners.delete(cb);
  }

  close(): void {
    void this.cancel().catch((error) => {
      this.emitError(error instanceof Error ? error : new Error(String(error)));
    });
  }

  private async run(options?: LiveSessionOptions): Promise<SessionFinalEvent> {
    try {
      const res = await this.open(options);
      if (!res.body) {
        throw new VoxDError("Live session stream did not include a response body.", "protocol_error");
      }

      let result: Record<string, unknown> | null = null;
      await readNDJSON(res.body, (message) => {
        if (typeof message.error === "string" && message.error) {
          throw new VoxDError(message.error, "live_session_error");
        }

        if (typeof message.event === "string") {
          this.handleEvent(message.event, asObject(message.data));
          return;
        }

        if (message.result && typeof message.result === "object") {
          result = asObject(message.result);
        }
      });

      const finalEvent = this.finalEvent ?? this.parseResult(result);
      if (!finalEvent) {
        throw new VoxDError("Live session ended without a final result.", "protocol_error");
      }
      return finalEvent;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.emitError(err);
      throw err;
    }
  }

  private handleEvent(event: string, data: Record<string, unknown>): void {
    switch (event) {
      case "session.state": {
        const payload: SessionStateEvent = {
          sessionId: String(data.sessionId ?? this.sessionId ?? ""),
          state: String(data.state ?? "error") as SessionStateEvent["state"],
          previous: (data.previous as SessionStateEvent["previous"]) ?? null,
          reason: typeof data.reason === "string" ? data.reason : undefined,
        };
        if (payload.sessionId) {
          this.sessionId = payload.sessionId;
        }
        for (const listener of this.stateListeners) {
          listener(payload);
        }
        break;
      }
      case "session.partial": {
        const payload: LiveSessionPartialEvent = {
          sessionId: String(data.sessionId ?? this.sessionId ?? ""),
          text: String(data.text ?? ""),
        };
        if (payload.sessionId) {
          this.sessionId = payload.sessionId;
        }
        for (const listener of this.partialListeners) {
          listener(payload);
        }
        break;
      }
      case "session.final": {
        const payload = this.parseResult(data);
        if (!payload) {
          return;
        }
        this.finalEvent = payload;
        this.sessionId = payload.sessionId || this.sessionId;
        for (const listener of this.finalListeners) {
          listener(payload);
        }
        break;
      }
    }
  }

  private parseResult(raw: Record<string, unknown> | null): SessionFinalEvent | null {
    if (!raw) {
      return null;
    }

    if (raw.cancelled) {
      throw new VoxDError(
        `Live session ${String(raw.sessionId ?? this.sessionId ?? "")} was cancelled.`,
        "session_cancelled",
      );
    }

    return {
      sessionId: String(raw.sessionId ?? this.sessionId ?? ""),
      text: String(raw.text ?? ""),
      durationMs: Number(raw.durationMs ?? raw.elapsedMs ?? 0),
      words: Array.isArray(raw.words) ? raw.words as TranscriptionResult["words"] : undefined,
      metrics: isMetrics(raw.metrics) ? raw.metrics : undefined,
    };
  }

  private emitError(error: Error): void {
    for (const listener of this.errorListeners) {
      listener(error);
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function inferFormat(mimeType: string): string | undefined {
  if (mimeType.includes("mp3") || mimeType.includes("mpeg")) return "mp3";
  if (mimeType.includes("wav")) return "wav";
  if (mimeType.includes("aac") || mimeType.includes("mp4")) return "aac";
  if (mimeType.includes("opus") || mimeType.includes("ogg")) return "opus";
  return undefined;
}

function mimeForFormat(format: string): string {
  switch (format) {
    case "mp3": return "audio/mpeg";
    case "wav": return "audio/wav";
    case "aac": return "audio/aac";
    case "opus": return "audio/ogg; codecs=opus";
    case "pcm16": return "audio/pcm";
    default: return "application/octet-stream";
  }
}

async function readNDJSON(
  stream: ReadableStream<Uint8Array>,
  onMessage: (message: Record<string, unknown>) => void,
): Promise<void> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });
      buffer = flushNDJSONBuffer(buffer, onMessage);
    }

    buffer += decoder.decode();
    const remainder = buffer.trim();
    if (remainder) {
      onMessage(parseNDJSONLine(remainder));
    }
  } finally {
    reader.releaseLock();
  }
}

function flushNDJSONBuffer(
  buffer: string,
  onMessage: (message: Record<string, unknown>) => void,
): string {
  let nextBuffer = buffer;
  while (true) {
    const newlineIndex = nextBuffer.indexOf("\n");
    if (newlineIndex === -1) {
      return nextBuffer;
    }

    const line = nextBuffer.slice(0, newlineIndex).trim();
    nextBuffer = nextBuffer.slice(newlineIndex + 1);
    if (!line) {
      continue;
    }
    onMessage(parseNDJSONLine(line));
  }
}

function parseNDJSONLine(line: string): Record<string, unknown> {
  try {
    return JSON.parse(line) as Record<string, unknown>;
  } catch {
    throw new VoxDError("Live session stream returned invalid JSON.", "protocol_error");
  }
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function isMetrics(value: unknown): value is TranscriptionResult["metrics"] {
  return Boolean(value && typeof value === "object");
}
