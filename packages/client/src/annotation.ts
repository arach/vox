import type { AttributedWordTiming, SpeakerSegment } from "./types.ts";

export function parseAttributedWordTimings(value: unknown): AttributedWordTiming[] {
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
      speakerId:
        typeof fields.speakerId === "string" && fields.speakerId.length > 0
          ? fields.speakerId
          : null,
    } satisfies AttributedWordTiming;
  }).filter((word) => word.word.length > 0);
}

export function parseSpeakerSegments(value: unknown): SpeakerSegment[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((entry) => {
    const segment = typeof entry === "object" && entry !== null ? entry : {};
    const fields = segment as Record<string, unknown>;
    return {
      speakerId: String(fields.speakerId ?? ""),
      start: Number(fields.start ?? 0),
      end: Number(fields.end ?? 0),
      confidence:
        fields.confidence === null || fields.confidence === undefined
          ? null
          : Number(fields.confidence),
    } satisfies SpeakerSegment;
  }).filter((segment) => segment.speakerId.length > 0);
}
