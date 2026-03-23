import { formatWordTimings } from "../src/index.ts";

describe("formatWordTimings", () => {
  it("renders an aligned timestamp table for CLI output", () => {
    const lines = formatWordTimings([
      { word: "hello", start: 0, end: 0.41, confidence: 0.98 },
      { word: "world", start: 0.42, end: 0.86, confidence: 0.97 },
    ]);

    expect(lines).toEqual([
      "timestamps (2 words):",
      "  start    end  conf  word",
      "  0.00s  0.41s  0.98  hello",
      "  0.42s  0.86s  0.97  world",
    ]);
  });

  it("handles unavailable timings without crashing", () => {
    expect(formatWordTimings([])).toEqual(["timestamps: unavailable"]);
  });
});
