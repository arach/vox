import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { createServer } from "net";
import { createVoxdClient } from "../src/client.js";

const E2E_ENABLED = process.env.VOX_E2E === "1";
const maybeDescribe = E2E_ENABLED ? describe : describe.skip;
const REPO_ROOT = join(import.meta.dir, "../../..");
const BRIDGE_BINARY = join(REPO_ROOT, "swift/.build/debug/voxbridge");
const TEST_ORIGIN = "http://localhost:3200";
const REFERENCE_DATE_SECONDS = 978307200;
const LIVE_RESULT = {
  sessionId: "session-1",
  text: "Browser live session bridge is working end to end.",
  elapsedMs: 42,
  words: [
    { word: "Browser", start: 0, end: 0.25 },
    { word: "live", start: 0.26, end: 0.45 },
    { word: "session", start: 0.46, end: 0.78 },
    { word: "bridge", start: 0.79, end: 1.02 },
    { word: "is", start: 1.03, end: 1.12 },
    { word: "working", start: 1.13, end: 1.55 },
    { word: "end", start: 1.56, end: 1.74 },
    { word: "to", start: 1.75, end: 1.82 },
    { word: "end", start: 1.83, end: 2.02 },
  ],
  metrics: {
    inferenceMs: 12,
    totalMs: 42,
    realtimeFactor: 0.21,
  },
};

maybeDescribe("Vox browser live-session e2e", () => {
  let browserClient: ReturnType<typeof createVoxdClient>;
  let bridge: Bun.Subprocess | null = null;
  let daemon: ReturnType<typeof startDaemonStub> | null = null;
  let tempHome = "";
  let bridgePort = 0;
  let daemonPort = 0;
  let fetchImpl = globalThis.fetch;

  beforeAll(async () => {
    if (!existsSync(BRIDGE_BINARY)) {
      throw new Error(`Missing bridge binary at ${BRIDGE_BINARY}. Run bun run build first.`);
    }

    tempHome = mkdtempSync(join(tmpdir(), "vox-browser-live-home-"));
    mkdirSync(tempHome, { recursive: true });
    writeFileSync(
      join(tempHome, "origins.json"),
      JSON.stringify({ origins: ["http://localhost:*"] }, null, 2),
    );

    daemonPort = await reservePort();
    bridgePort = await reservePort();

    daemon = startDaemonStub(daemonPort);
    writeRuntimeInfo(tempHome, daemonPort);

    bridge = Bun.spawn([BRIDGE_BINARY, "--port", String(bridgePort)], {
      cwd: REPO_ROOT,
      env: {
        ...process.env,
        VOX_HOME: tempHome,
      },
      stdout: "ignore",
      stderr: "ignore",
    });

    fetchImpl = globalThis.fetch;
    globalThis.fetch = ((input, init) => {
      const headers = new Headers(init?.headers);
      headers.set("Origin", TEST_ORIGIN);
      return fetchImpl(input, {
        ...init,
        headers,
      });
    }) as typeof fetch;

    browserClient = createVoxdClient({
      clientId: "vox-browser-e2e",
      port: bridgePort,
    });

    await waitForBridge(browserClient);
  }, 300_000);

  afterAll(async () => {
    globalThis.fetch = fetchImpl;

    if (bridge && bridge.exitCode === null) {
      bridge.kill();
      await bridge.exited;
    }

    daemon?.stop();

    if (tempHome) {
      rmSync(tempHome, { recursive: true, force: true });
    }
  });

  test("streams a browser live session through the HTTP bridge into the daemon protocol", async () => {
    const capabilities = await browserClient.capabilities();
    expect(capabilities.running).toBe(true);
    expect(capabilities.features.realtime).toBe(true);

    const session = browserClient.createLiveSession();
    const states: string[] = [];
    let finalEvents = 0;
    let resolveRecording!: () => void;
    const recording = new Promise<void>((resolve) => {
      resolveRecording = resolve;
    });

    session.onState((event) => {
      states.push(event.state);
      if (event.state === "recording") {
        resolveRecording();
      }
    });
    session.onFinal(() => {
      finalEvents += 1;
    });

    const resultPromise = session.start({ modelId: "parakeet:v3" });

    await recording;

    const status = await browserClient.getLiveSessionStatus();
    expect(status?.clientId).toBe("vox-browser-e2e");
    expect(status?.modelId).toBe("parakeet:v3");
    expect(status?.state).toBe("recording");
    expect(status?.sessionId).toBe(session.id);

    await session.stop();
    const result = await resultPromise;

    expect(finalEvents).toBe(1);
    expect(states).toContain("starting");
    expect(states).toContain("recording");
    expect(states).toContain("processing");
    expect(states).toContain("done");
    expect(normalize(result.text)).toContain("browser live session bridge");
    expect(normalize(result.text)).toContain("end to end");
    expect(result.metrics).toEqual(LIVE_RESULT.metrics);
    expect(result.words).toEqual(LIVE_RESULT.words);
    expect(await browserClient.getLiveSessionStatus()).toBeNull();
  }, 300_000);
});

function startDaemonStub(port: number) {
  type SessionRecord = {
    sessionId: string;
    connectionId: string;
    clientId: string;
    modelId: string;
    startedAt: string;
    state: string;
    requestId: string;
    ws: ServerWebSocket<unknown>;
  };

  let currentSession: SessionRecord | null = null;
  const connectionId = "bridge-connection-1";
  const server = Bun.serve({
    port,
    fetch(request, server) {
      if (server.upgrade(request)) {
        return;
      }
      return new Response("Not Found", { status: 404 });
    },
    websocket: {
      message(ws, rawMessage) {
        const message = JSON.parse(String(rawMessage)) as {
          id: string;
          method: string;
          params?: Record<string, unknown>;
        };

        switch (message.method) {
          case "health":
            sendResult(ws, message.id, {
              service: "Vox",
              version: "0.1.0",
              port,
              pid: process.pid,
              startedAt: new Date().toISOString(),
            });
            return;
          case "models.list":
            sendResult(ws, message.id, {
              models: [
                {
                  id: "parakeet:v3",
                  name: "Parakeet",
                  backend: "parakeet",
                  installed: true,
                  preloaded: true,
                  available: true,
                },
              ],
            });
            return;
          case "transcribe.sessionStatus":
            sendResult(ws, message.id, {
              session: currentSession
                ? {
                    sessionId: currentSession.sessionId,
                    connectionId: currentSession.connectionId,
                    clientId: currentSession.clientId,
                    modelId: currentSession.modelId,
                    startedAt: currentSession.startedAt,
                    state: currentSession.state,
                  }
                : null,
            });
            return;
          case "transcribe.startSession": {
            if (currentSession) {
              sendError(ws, message.id, "live_session_busy");
              return;
            }

            currentSession = {
              sessionId: LIVE_RESULT.sessionId,
              connectionId,
              clientId: String(message.params?.clientId ?? "unknown"),
              modelId: String(message.params?.modelId ?? "parakeet:v3"),
              startedAt: new Date().toISOString(),
              state: "starting",
              requestId: message.id,
              ws,
            };

            sendEvent(ws, message.id, "session.state", {
              sessionId: currentSession.sessionId,
              state: "starting",
              previous: null,
            });
            currentSession.state = "recording";
            sendEvent(ws, message.id, "session.state", {
              sessionId: currentSession.sessionId,
              state: "recording",
              previous: "starting",
            });
            return;
          }
          case "transcribe.stopSession": {
            if (!currentSession) {
              sendError(ws, message.id, "No active live session");
              return;
            }

            currentSession.state = "processing";
            sendEvent(currentSession.ws, currentSession.requestId, "session.state", {
              sessionId: currentSession.sessionId,
              state: "processing",
              previous: "recording",
            });
            sendEvent(currentSession.ws, currentSession.requestId, "session.final", LIVE_RESULT);
            sendEvent(currentSession.ws, currentSession.requestId, "session.state", {
              sessionId: currentSession.sessionId,
              state: "done",
              previous: "processing",
            });
            sendResult(currentSession.ws, currentSession.requestId, LIVE_RESULT);
            sendResult(ws, message.id, {
              stopped: true,
              sessionId: currentSession.sessionId,
            });
            currentSession = null;
            return;
          }
          case "transcribe.cancelSession": {
            if (!currentSession) {
              sendError(ws, message.id, "No active live session");
              return;
            }

            sendEvent(currentSession.ws, currentSession.requestId, "session.state", {
              sessionId: currentSession.sessionId,
              state: "cancelled",
              previous: currentSession.state,
            });
            sendResult(currentSession.ws, currentSession.requestId, {
              cancelled: true,
              sessionId: currentSession.sessionId,
            });
            sendResult(ws, message.id, {
              cancelled: true,
              sessionId: currentSession.sessionId,
            });
            currentSession = null;
            return;
          }
          default:
            sendError(ws, message.id, `Unknown method: ${message.method}`);
        }
      },
    },
  });

  return {
    stop() {
      server.stop(true);
    },
  };
}

function sendResult(ws: ServerWebSocket<unknown>, id: string, result: Record<string, unknown>): void {
  ws.send(JSON.stringify({ id, result }));
}

function sendError(ws: ServerWebSocket<unknown>, id: string, error: string): void {
  ws.send(JSON.stringify({ id, error }));
}

function sendEvent(
  ws: ServerWebSocket<unknown>,
  id: string,
  event: string,
  data: Record<string, unknown>,
): void {
  ws.send(JSON.stringify({ id, event, data }));
}

function writeRuntimeInfo(tempHome: string, port: number): void {
  writeFileSync(
    join(tempHome, "runtime.json"),
    JSON.stringify({
      version: "0.1.0",
      serviceName: "Vox",
      port,
      pid: process.pid,
      startedAt: Date.now() / 1000 - REFERENCE_DATE_SECONDS,
    }),
  );
}

async function reservePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close();
        reject(new Error("Failed to reserve an ephemeral port."));
        return;
      }

      const { port } = address;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function waitForBridge(client: ReturnType<typeof createVoxdClient>): Promise<void> {
  const deadline = Date.now() + 15_000;
  let lastError: Error | null = null;

  while (Date.now() < deadline) {
    try {
      const capabilities = await client.capabilities();
      if (capabilities.running) {
        return;
      }
      lastError = new Error("Bridge is reachable but daemon is not reported as running.");
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
    }
    await Bun.sleep(200);
  }

  throw lastError ?? new Error("Timed out waiting for Vox bridge.");
}

function normalize(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
