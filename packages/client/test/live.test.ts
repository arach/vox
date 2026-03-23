import { VoxLiveSession } from "../src/live.ts";

describe("VoxLiveSession", () => {
  it("emits the final event once when the server sends a final progress event and reply", async () => {
    const events: string[] = [];
    const session = new VoxLiveSession({
      callStreaming: async (_method, _params, onProgress) => {
        onProgress("session.state", {
          sessionId: "session-1",
          state: "recording",
          previous: "starting",
        });
        onProgress("session.final", {
          sessionId: "session-1",
          text: "hello world",
          elapsedMs: 42,
          words: [
            { word: "hello", start: 0, end: 0.4, confidence: 0.97 },
            { word: "world", start: 0.41, end: 0.8, confidence: 0.96 },
          ],
        });
        return {
          sessionId: "session-1",
          text: "hello world",
          elapsedMs: 42,
          words: [
            { word: "hello", start: 0, end: 0.4, confidence: 0.97 },
            { word: "world", start: 0.41, end: 0.8, confidence: 0.96 },
          ],
        };
      },
      call: async () => ({ stopped: true }),
    } as never);

    session.on("final", ({ text, words }) => {
      events.push(`${text}:${words.length}`);
    });

    const result = await session.start();

    expect(result.text).toBe("hello world");
    expect(result.words).toEqual([
      { word: "hello", start: 0, end: 0.4, confidence: 0.97 },
      { word: "world", start: 0.41, end: 0.8, confidence: 0.96 },
    ]);
    expect(events).toEqual(["hello world:2"]);
  });

  it("falls back to the reply payload for words when no final progress event arrives", async () => {
    const session = new VoxLiveSession({
      callStreaming: async () => ({
        sessionId: "session-2",
        text: "fallback path",
        elapsedMs: 51,
        words: [
          { word: "fallback", start: 0, end: 0.48, confidence: 0.95 },
          { word: "path", start: 0.49, end: 0.8, confidence: 0.94 },
        ],
      }),
      call: async () => ({ stopped: true }),
    } as never);

    const result = await session.start();

    expect(result.words).toEqual([
      { word: "fallback", start: 0, end: 0.48, confidence: 0.95 },
      { word: "path", start: 0.49, end: 0.8, confidence: 0.94 },
    ]);
  });
});
