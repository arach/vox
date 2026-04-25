import { parseTranscriptionMetrics } from "../src/metrics.ts";
import { parseWordTimings } from "../src/words.ts";

describe("parseTranscriptionMetrics", () => {
  it("uses the elapsed fallback when totalMs is missing", () => {
    expect(
      parseTranscriptionMetrics(
        {
          traceId: "trace-1",
          audioDurationMs: 2400,
          inputBytes: 8192,
          wasPreloaded: true,
          fileCheckMs: 2,
          modelCheckMs: 1,
          modelLoadMs: 0,
          audioLoadMs: 3,
          audioPrepareMs: 4,
          inferenceMs: 90,
        },
        107,
      ),
    ).toEqual({
      traceId: "trace-1",
      audioDurationMs: 2400,
      inputBytes: 8192,
      wasPreloaded: true,
      fileCheckMs: 2,
      modelCheckMs: 1,
      modelLoadMs: 0,
      audioLoadMs: 3,
      audioPrepareMs: 4,
      inferenceMs: 90,
      totalMs: 107,
      realtimeFactor: 0,
    });
  });

  it("returns undefined for non-object values", () => {
    expect(parseTranscriptionMetrics(undefined, 50)).toBeUndefined();
    expect(parseTranscriptionMetrics("oops", 50)).toBeUndefined();
  });
});

describe("parseWordTimings", () => {
  it("filters empty words and defaults missing numeric fields", () => {
    expect(
      parseWordTimings([
        { word: "hello", start: 0.01, end: 0.2, confidence: 0.98 },
        { word: "", start: 0.21, end: 0.4, confidence: 0.91 },
        { start: 0.41, end: 0.8 },
        { word: "world" },
      ]),
    ).toEqual([
      { word: "hello", start: 0.01, end: 0.2, confidence: 0.98 },
      { word: "world", start: 0, end: 0, confidence: 0 },
    ]);
  });

  it("returns an empty array for non-array values", () => {
    expect(parseWordTimings(undefined)).toEqual([]);
    expect(parseWordTimings({ word: "hello" })).toEqual([]);
  });
});
