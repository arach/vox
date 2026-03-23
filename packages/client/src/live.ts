import { Emitter } from "./events.ts";
import { parseTranscriptionMetrics } from "./metrics.ts";
import type { VoxClient } from "./client.ts";
import type { LiveSessionEvents, SessionFinalEvent, SessionStateEvent } from "./types.ts";
import { parseWordTimings } from "./words.ts";

export class VoxLiveSession extends Emitter<LiveSessionEvents> {
  private sessionId: string | null = null;
  private finalEvent: SessionFinalEvent | null = null;

  constructor(private readonly client: VoxClient) {
    super();
  }

  get id(): string | null {
    return this.sessionId;
  }

  async start(params?: Record<string, unknown>): Promise<SessionFinalEvent> {
    this.finalEvent = null;
    try {
      const result = await this.client.callStreaming(
        "transcribe.startSession",
        params,
        (event, data) => this.handleProgress(event, data),
      );

      const finalEvent = this.finalEvent ?? {
        sessionId: String(result.sessionId ?? this.sessionId ?? ""),
        text: String(result.text ?? ""),
        elapsedMs: Number(result.elapsedMs ?? 0),
        metrics: parseTranscriptionMetrics(result.metrics, Number(result.elapsedMs ?? 0)),
        words: parseWordTimings(result.words),
      };
      return finalEvent;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.emit("error", { error: err });
      throw err;
    }
  }

  async stop(): Promise<void> {
    await this.client.call("transcribe.stopSession", this.sessionId ? { sessionId: this.sessionId } : undefined);
  }

  async cancel(): Promise<void> {
    await this.client.call("transcribe.cancelSession", this.sessionId ? { sessionId: this.sessionId } : undefined);
  }

  private handleProgress(event: string, data: Record<string, unknown>): void {
    switch (event) {
      case "session.state": {
        const payload: SessionStateEvent = {
          sessionId: String(data.sessionId ?? this.sessionId ?? ""),
          state: data.state as SessionStateEvent["state"],
          previous: (data.previous as SessionStateEvent["previous"]) ?? null,
        };
        this.sessionId = payload.sessionId || this.sessionId;
        this.emit("state", payload);
        break;
      }
      case "session.partial": {
        const sessionId = String(data.sessionId ?? this.sessionId ?? "");
        if (sessionId) {
          this.sessionId = sessionId;
        }
        this.emit("partial", { sessionId, text: String(data.text ?? "") });
        break;
      }
      case "session.final": {
        const payload: SessionFinalEvent = {
          sessionId: String(data.sessionId ?? this.sessionId ?? ""),
          text: String(data.text ?? ""),
          elapsedMs: Number(data.elapsedMs ?? 0),
          metrics: parseTranscriptionMetrics(data.metrics, Number(data.elapsedMs ?? 0)),
          words: parseWordTimings(data.words),
        };
        this.finalEvent = payload;
        this.sessionId = payload.sessionId || this.sessionId;
        this.emit("final", payload);
        break;
      }
    }
  }
}
