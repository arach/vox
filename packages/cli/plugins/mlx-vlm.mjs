#!/usr/bin/env node

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

const MODEL_ID = process.env.VOX_MLX_VLM_MODEL ?? "mlx-community/gemma-4-E2B-it-4bit";
const PYTHON = process.env.VOX_MLX_VLM_PYTHON ?? "python3";

function respond(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function respondError(id, code, message) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n");
}

function notify(method, params) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

function run(command, args, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(stderr.trim() || stdout.trim() || `${command} exited ${code}`));
    });
    if (input) {
      child.stdin.end(input);
    } else {
      child.stdin.end();
    }
  });
}

async function pythonAvailable() {
  try {
    await run(PYTHON, ["-c", "import mlx_vlm"]);
    return true;
  } catch {
    return false;
  }
}

function modelInfo(available) {
  return {
    id: "gemma-4-e2b-it",
    name: "Gemma 4 E2B",
    backend: "mlx-vlm",
    installed: available,
    preloaded: false,
    available,
  };
}

async function transcribe(path) {
  const prompt = "Transcribe the spoken audio. Return only the transcript text.";
  const script = `
import sys
from mlx_vlm import load, generate
model, processor = load(${JSON.stringify(MODEL_ID)})
result = generate(model, processor, prompt=${JSON.stringify(prompt)}, audio=${JSON.stringify(path)}, max_tokens=512)
text = result if isinstance(result, str) else getattr(result, "text", None) or str(result)
print(text)
`;
  const { stdout } = await run(PYTHON, ["-c", script]);
  return stdout.trim();
}

async function handle(req) {
  const available = await pythonAvailable();
  switch (req.method) {
    case "models":
      respond(req.id, { models: [modelInfo(available)] });
      return;
    case "install":
    case "preload": {
      const modelId = req.params?.modelId ?? "gemma-4-e2b-it";
      notify("progress", { modelId, progress: 0.4, status: available ? "checking" : "missing mlx-vlm" });
      notify("progress", { modelId, progress: 1.0, status: available ? "ready" : "unavailable" });
      respond(req.id, { model: modelInfo(available) });
      return;
    }
    case "transcribe": {
      const path = req.params?.path;
      const modelId = req.params?.modelId ?? "gemma-4-e2b-it";
      if (!path || !existsSync(path)) {
        respondError(req.id, 6, `Audio file not found at ${path ?? "(missing)"}`);
        return;
      }
      if (!available) {
        respondError(req.id, 12, "mlx-vlm is not installed in the plugin Python. Set VOX_MLX_VLM_PYTHON to a venv that has mlx-vlm.");
        return;
      }
      const started = Date.now();
      const text = await transcribe(path);
      const elapsed = Date.now() - started;
      respond(req.id, {
        modelId,
        text,
        elapsedMs: elapsed,
        metrics: {
          traceId: Math.random().toString(36).slice(2, 10),
          audioDurationMs: 0,
          inputBytes: 0,
          wasPreloaded: false,
          fileCheckMs: 0,
          modelCheckMs: 0,
          modelLoadMs: 0,
          audioLoadMs: 0,
          audioPrepareMs: 0,
          inferenceMs: elapsed,
          totalMs: elapsed,
        },
        words: [],
      });
      return;
    }
    default:
      respondError(req.id, -32601, `Unknown method: ${req.method}`);
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      handle(JSON.parse(line)).catch((error) => {
        process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
      });
    } catch {
      process.stderr.write(`Failed to parse: ${line}\n`);
    }
  }
});
