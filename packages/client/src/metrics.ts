import type { TranscriptionMetrics } from "./types.ts";

export function parseTranscriptionMetrics(
  value: unknown,
  fallbackElapsedMs: number,
): TranscriptionMetrics | undefined {
  if (!value || typeof value !== "object") {
    return undefined;
  }

  const raw = value as Record<string, unknown>;
  return {
    traceId: String(raw.traceId ?? ""),
    audioDurationMs: Number(raw.audioDurationMs ?? 0),
    inputBytes: Number(raw.inputBytes ?? 0),
    wasPreloaded: Boolean(raw.wasPreloaded),
    fileCheckMs: Number(raw.fileCheckMs ?? 0),
    modelCheckMs: Number(raw.modelCheckMs ?? 0),
    modelLoadMs: Number(raw.modelLoadMs ?? 0),
    audioLoadMs: Number(raw.audioLoadMs ?? 0),
    audioPrepareMs: Number(raw.audioPrepareMs ?? 0),
    inferenceMs: Number(raw.inferenceMs ?? 0),
    totalMs: Number(raw.totalMs ?? fallbackElapsedMs),
    realtimeFactor: Number(raw.realtimeFactor ?? 0),
  };
}
