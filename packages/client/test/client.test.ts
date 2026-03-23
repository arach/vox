import { VoxClient } from "../src/client.ts";
import { STREAM_TIMEOUT_MS } from "../src/constants.ts";

describe("VoxClient", () => {
  it("uses the streaming timeout budget for file transcription", async () => {
    const calls: Array<{ method: string; params: Record<string, unknown>; timeoutMs: number }> = [];
    const client = new VoxClient({ clientId: "test-client" }) as unknown as {
      transport: {
        call: (
          method: string,
          params: Record<string, unknown>,
          timeoutMs: number,
        ) => Promise<Record<string, unknown>>;
      };
      transcribeFile: (path: string, modelId?: string) => Promise<{ text: string }>;
    };

    client.transport = {
      call: async (method, params, timeoutMs) => {
        calls.push({ method, params, timeoutMs });
        return {
          modelId: "parakeet:v3",
          text: "ok",
          elapsedMs: 12,
          words: [
            { word: "ok", start: 0.01, end: 0.2, confidence: 0.99 },
          ],
        };
      },
    };

    const result = await client.transcribeFile("/tmp/sample.wav");

    expect(result.text).toBe("ok");
    expect(result.words).toEqual([
      { word: "ok", start: 0.01, end: 0.2, confidence: 0.99 },
    ]);
    expect(calls).toEqual([
      {
        method: "transcribe.file",
        params: {
          clientId: "test-client",
          path: "/tmp/sample.wav",
          modelId: "parakeet:v3",
        },
        timeoutMs: STREAM_TIMEOUT_MS,
      },
    ]);
  });

  it("parses live session status responses", async () => {
    const client = new VoxClient({ clientId: "test-client" }) as unknown as {
      call: (method: string, params?: Record<string, unknown>) => Promise<Record<string, unknown>>;
      getLiveSessionStatus: () => Promise<unknown>;
    };

    client.call = async (method) => {
      expect(method).toBe("transcribe.sessionStatus");
      return {
        session: {
          sessionId: "session-1",
          connectionId: "conn-1",
          clientId: "openscout-app",
          modelId: "parakeet:v3",
          startedAt: "2026-03-23T16:44:48Z",
          state: "recording",
        },
      };
    };

    expect(await client.getLiveSessionStatus()).toEqual({
      sessionId: "session-1",
      connectionId: "conn-1",
      clientId: "openscout-app",
      modelId: "parakeet:v3",
      startedAt: "2026-03-23T16:44:48Z",
      state: "recording",
    });
  });

  it("cancels the active live session without requiring a session id", async () => {
    const calls: Array<{ method: string; params?: Record<string, unknown> }> = [];
    const client = new VoxClient({ clientId: "test-client" }) as unknown as {
      call: (method: string, params?: Record<string, unknown>) => Promise<Record<string, unknown>>;
      cancelLiveSession: (sessionId?: string) => Promise<unknown>;
    };

    client.call = async (method, params) => {
      calls.push({ method, params });
      return {
        cancelled: true,
        sessionId: "session-1",
      };
    };

    expect(await client.cancelLiveSession()).toEqual({
      cancelled: true,
      sessionId: "session-1",
    });
    expect(calls).toEqual([
      {
        method: "transcribe.cancelSession",
        params: undefined,
      },
    ]);
  });
});
