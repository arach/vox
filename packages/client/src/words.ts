import type { WordTiming } from "./types.ts";

export function parseWordTimings(value: unknown): WordTiming[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((entry) => {
    const word = typeof entry === "object" && entry !== null ? entry : {};
    const fields = word as Record<string, unknown>;
    return {
      word: String(fields.word ?? ""),
      start: Number(fields.start ?? 0),
      end: Number(fields.end ?? 0),
      confidence: Number(fields.confidence ?? 0),
    } satisfies WordTiming;
  }).filter((word) => word.word.length > 0);
}
