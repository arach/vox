import type {
  VoxHealth,
  VoxCapabilities,
  CreateJobOptions,
  JobAccepted,
  JobStatus,
  AlignmentResult,
  CompanionState,
  VoxDClientOptions,
} from "./types.js";

const DEFAULT_PORT = 43115;
const DEFAULT_PROBE_TIMEOUT = 2000;
const DEFAULT_POLL_INTERVAL = 500;

/**
 * Browser client for the Vox Companion local transcription runtime.
 *
 * @example
 * ```ts
 * import { VoxDClient } from "@voxd/client";
 *
 * const vox = new VoxDClient();
 *
 * if (await vox.probe()) {
 *   const caps = await vox.capabilities();
 *   if (caps.features.alignment) {
 *     const result = await vox.align({
 *       source: { audioUrl: "https://example.com/clip.mp3" },
 *     });
 *     console.log(result.words);
 *   }
 * }
 * ```
 */
export class VoxDClient {
  private readonly base: string;
  private readonly probeTimeout: number;
  private readonly pollInterval: number;
  private _state: CompanionState = "unknown";

  constructor(options?: VoxDClientOptions) {
    const port = options?.port ?? DEFAULT_PORT;
    this.base = `http://127.0.0.1:${port}`;
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

  // ── Jobs ─────────────────────────────────────────────────

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
   * Submit an alignment job and wait for the result.
   * This is the high-level convenience method most apps should use.
   *
   * @returns The alignment result with word-level timestamps.
   * @throws If the job fails or the companion is unreachable.
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
