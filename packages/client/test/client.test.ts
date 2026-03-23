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
});
