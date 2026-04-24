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

  it("uses the streaming timeout budget for synthesis and decodes audio bytes", async () => {
    const calls: Array<{ method: string; params: Record<string, unknown>; timeoutMs: number }> = [];
    const client = new VoxClient({ clientId: "test-client" }) as unknown as {
      transport: {
        call: (
          method: string,
          params: Record<string, unknown>,
          timeoutMs: number,
        ) => Promise<Record<string, unknown>>;
      };
      synthesize: (text: string, options?: Record<string, unknown>) => Promise<{ audioBytes: number; voiceId: string }>;
    };

    client.transport = {
      call: async (method, params, timeoutMs) => {
        calls.push({ method, params, timeoutMs });
        return {
          modelId: "avspeech:system",
          voiceId: "com.apple.speech.synthesis.voice.Alex",
          format: "wav",
          contentType: "audio/wav",
          audioBase64: Buffer.from([0x52, 0x49, 0x46, 0x46]).toString("base64"),
          audioBytes: 4,
          elapsedMs: 18,
          metrics: {
            traceId: "trace-1",
            characterCount: 11,
            audioDurationMs: 500,
            outputBytes: 4,
            wasPreloaded: true,
            modelCheckMs: 1,
            modelLoadMs: 0,
            voiceResolveMs: 1,
            synthesisMs: 12,
            totalMs: 18,
          },
        };
      },
    };

    const result = await client.synthesize("hello world");

    expect(result.audioBytes).toBe(4);
    expect(result.voiceId).toBe("com.apple.speech.synthesis.voice.Alex");
    expect([...result.audio]).toEqual([0x52, 0x49, 0x46, 0x46]);
    expect(calls).toEqual([
      {
        method: "synthesize.generate",
        params: {
          clientId: "test-client",
          text: "hello world",
          modelId: "avspeech:system",
          voiceId: undefined,
          format: "wav",
          speed: undefined,
          instructions: undefined,
        },
        timeoutMs: STREAM_TIMEOUT_MS,
      },
    ]);
  });

  it("lists synthesis voices through the daemon route", async () => {
    const client = new VoxClient({ clientId: "test-client" }) as unknown as {
      call: (method: string, params?: Record<string, unknown>) => Promise<Record<string, unknown>>;
      listVoices: (modelId?: string) => Promise<unknown>;
    };

    client.call = async (method, params) => {
      expect(method).toBe("synthesize.voices");
      expect(params).toEqual({ modelId: "avspeech:system" });
      return {
        voices: [
          {
            id: "com.apple.speech.synthesis.voice.Alex",
            name: "Alex",
            modelId: "avspeech:system",
            backend: "avspeech",
            available: true,
            default: true,
          },
        ],
      };
    };

    expect(await client.listVoices("avspeech:system")).toEqual([
      {
        id: "com.apple.speech.synthesis.voice.Alex",
        name: "Alex",
        modelId: "avspeech:system",
        backend: "avspeech",
        available: true,
        default: true,
      },
    ]);
  });
});
