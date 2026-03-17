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
        });
        return {
          sessionId: "session-1",
          text: "hello world",
          elapsedMs: 42,
        };
      },
      call: async () => ({ stopped: true }),
    } as never);

    session.on("final", ({ text }) => {
      events.push(text);
    });

    const result = await session.start();

    expect(result.text).toBe("hello world");
    expect(events).toEqual(["hello world"]);
  });
});
