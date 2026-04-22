import { afterEach, describe, expect, it, mock } from "bun:test";
import { VoxDError, createVoxdClient } from "../src/client.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("VoxD live sessions", () => {
  it("emits the final event once when the bridge streams session progress and a final result", async () => {
    const events: string[] = [];

    globalThis.fetch = mock(async () => {
      return streamResponse([
        { event: "session.state", data: { sessionId: "session-1", state: "recording", previous: "starting" } },
        { event: "session.final", data: { sessionId: "session-1", text: "hello world", durationMs: 42, words: [{ word: "hello", start: 0, end: 0.4 }, { word: "world", start: 0.41, end: 0.8 }] } },
        { result: { sessionId: "session-1", text: "hello world", durationMs: 42, words: [{ word: "hello", start: 0, end: 0.4 }, { word: "world", start: 0.41, end: 0.8 }] } },
      ]);
    }) as typeof fetch;

    const client = createVoxdClient({ baseUrl: "http://127.0.0.1:43115" });
    const session = client.createLiveSession();

    session.onFinal(({ text, words }) => {
      events.push(`${text}:${words?.length ?? 0}`);
    });

    const result = await session.start();

    expect(result.text).toBe("hello world");
    expect(result.words).toEqual([
      { word: "hello", start: 0, end: 0.4 },
      { word: "world", start: 0.41, end: 0.8 },
    ]);
    expect(events).toEqual(["hello world:2"]);
  });

  it("rejects cancelled live sessions with a typed error", async () => {
    const errors: Error[] = [];

    globalThis.fetch = mock(async () => {
      return streamResponse([
        { event: "session.state", data: { sessionId: "session-2", state: "cancelled", previous: "recording" } },
        { result: { sessionId: "session-2", cancelled: true } },
      ]);
    }) as typeof fetch;

    const client = createVoxdClient({ baseUrl: "http://127.0.0.1:43115" });
    const session = client.createLiveSession();
    session.onError((error) => {
      errors.push(error);
    });

    await expect(session.start()).rejects.toMatchObject({
      code: "session_cancelled",
    } satisfies Partial<VoxDError>);
    expect(errors).toHaveLength(1);
  });
});

function streamResponse(lines: Array<Record<string, unknown>>): Response {
  return new Response(
    new ReadableStream({
      start(controller) {
        const encoder = new TextEncoder();
        for (const line of lines) {
          controller.enqueue(encoder.encode(`${JSON.stringify(line)}\n`));
        }
        controller.close();
      },
    }),
    {
      status: 200,
      headers: {
        "Content-Type": "application/x-ndjson",
      },
    },
  );
}
