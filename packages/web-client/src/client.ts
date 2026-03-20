import type {
  VoxHealth,
  VoxCapabilities,
  CreateJobOptions,
  JobAccepted,
  JobStatus,
  AlignmentResult,
  TranscribeOptions,
  TranscriptionResult,
  CompanionState,
  VoxDClientOptions,
} from "./types.js";

const DEFAULT_PORT = 43115;
const DEFAULT_PROBE_TIMEOUT = 2000;
const DEFAULT_POLL_INTERVAL = 500;

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
  private readonly probeTimeout: number;
  private readonly pollInterval: number;
  private _state: CompanionState = "unknown";

  constructor(options?: VoxDClientOptions) {
    if (options?.baseUrl) {
      this.base = options.baseUrl.replace(/\/$/, "");
    } else {
      const port = options?.port ?? DEFAULT_PORT;
      this.base = `http://127.0.0.1:${port}`;
    }
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
    if (metadata) form.append("metadata", JSON.stringify(metadata));

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
      body: JSON.stringify(options),
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
      | "job_failed"
      | "no_result"
      | "timeout",
  ) {
    super(message);
    this.name = "VoxDError";
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
