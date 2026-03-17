/**
 * Vox Provider Template — Echo Provider
 *
 * Minimal example of a Vox external provider that speaks JSON-RPC 2.0
 * over stdin/stdout. This echo provider returns the file path as text,
 * useful for testing the provider protocol without a real ASR engine.
 *
 * Usage:
 *   bun run index.ts
 *
 * Wire it into ~/.vox/providers.json:
 *   {
 *     "providers": [
 *       { "id": "parakeet", "builtin": true, "models": ["parakeet:v3"] },
 *       {
 *         "id": "template",
 *         "command": ["bun", "run", "/path/to/examples/provider-template/index.ts"],
 *         "models": ["template:echo"]
 *       }
 *     ]
 *   }
 */

interface JsonRpcRequest {
  jsonrpc: string;
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

interface JsonRpcResponse {
  jsonrpc: string;
  id: number;
  result?: unknown;
  error?: { code: number; message: string };
}

interface JsonRpcNotification {
  jsonrpc: string;
  method: string;
  params: Record<string, unknown>;
}

function respond(id: number, result: unknown): void {
  const response: JsonRpcResponse = { jsonrpc: "2.0", id, result };
  process.stdout.write(JSON.stringify(response) + "\n");
}

function respondError(id: number, code: number, message: string): void {
  const response: JsonRpcResponse = {
    jsonrpc: "2.0",
    id,
    error: { code, message },
  };
  process.stdout.write(JSON.stringify(response) + "\n");
}

function notify(method: string, params: Record<string, unknown>): void {
  const notification: JsonRpcNotification = { jsonrpc: "2.0", method, params };
  process.stdout.write(JSON.stringify(notification) + "\n");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const MODEL = {
  id: "template:echo",
  name: "Echo Provider",
  backend: "template",
  installed: true,
  preloaded: true,
  available: true,
};

async function handleRequest(req: JsonRpcRequest): Promise<void> {
  switch (req.method) {
    case "models":
      respond(req.id, { models: [MODEL] });
      break;

    case "install": {
      const modelId =
        (req.params?.modelId as string) ?? "template:echo";
      notify("progress", { modelId, progress: 0.5, status: "installing" });
      await sleep(100);
      notify("progress", { modelId, progress: 1.0, status: "ready" });
      respond(req.id, { model: MODEL });
      break;
    }

    case "preload": {
      const modelId =
        (req.params?.modelId as string) ?? "template:echo";
      notify("progress", { modelId, progress: 0.5, status: "loading" });
      await sleep(50);
      notify("progress", { modelId, progress: 1.0, status: "ready" });
      respond(req.id, { model: MODEL });
      break;
    }

    case "transcribe": {
      const path = req.params?.path as string;
      const modelId =
        (req.params?.modelId as string) ?? "template:echo";
      const start = Date.now();

      // Echo provider: return the file path as the transcription text
      const elapsed = Date.now() - start;
      respond(req.id, {
        modelId,
        text: `[echo] ${path}`,
        elapsedMs: elapsed,
        metrics: {
          traceId: Math.random().toString(36).slice(2, 10),
          audioDurationMs: 0,
          inputBytes: 0,
          wasPreloaded: true,
          fileCheckMs: 0,
          modelCheckMs: 0,
          modelLoadMs: 0,
          audioLoadMs: 0,
          audioPrepareMs: 0,
          inferenceMs: elapsed,
          totalMs: elapsed,
        },
      });
      break;
    }

    default:
      respondError(req.id, -32601, `Unknown method: ${req.method}`);
  }
}

// Read stdin line by line
const decoder = new TextDecoder();
let buffer = "";

process.stdin.on("data", (chunk: Buffer) => {
  buffer += decoder.decode(chunk, { stream: true });
  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const req = JSON.parse(trimmed) as JsonRpcRequest;
      handleRequest(req);
    } catch (err) {
      process.stderr.write(`Failed to parse: ${trimmed}\n`);
    }
  }
});

process.stderr.write("Vox echo provider started\n");
