#!/usr/bin/env bun

import React, { useState, useEffect, useCallback, useRef } from "react";
import { createCliRenderer } from "@opentui/core";
import { createRoot, useKeyboard, useRenderer, useTerminalDimensions } from "@opentui/react";
import { VoxClient } from "@vox/client";
import type { FileTranscriptionResult } from "@vox/client";
import { existsSync } from "fs";
import { basename, resolve } from "path";
import { execSync } from "child_process";

// ── Types ─────────────────────────────────────────────────────────────────────

interface TranscriptionEntry {
  id: number;
  file: string;
  status: "pending" | "running" | "done" | "error";
  result?: FileTranscriptionResult;
  error?: string;
  startedAt?: number;
  wallMs?: number;
}

interface LogEntry {
  id: number;
  time: string;
  level: "info" | "ok" | "warn" | "error";
  message: string;
}

type ConnectionState = "connecting" | "connected" | "failed";
type ModelState = "idle" | "loading" | "ready" | "skipped";

// ── Helpers ───────────────────────────────────────────────────────────────────

const ORIGINAL_CWD = process.env.INIT_CWD ?? process.cwd();

function resolvePath(filePath: string): string {
  return resolve(ORIGINAL_CWD, filePath.replace(/\\ /g, " ").replace(/^['"]|['"]$/g, ""));
}

function fmtMs(ms: number): string {
  return ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(1)}s`;
}

function ts(): string {
  const d = new Date();
  return [d.getHours(), d.getMinutes(), d.getSeconds()].map((n) => String(n).padStart(2, "0")).join(":");
}

let logId = 0;
const client = new VoxClient({ clientId: "transcribe-tui" });

// ── Colors ────────────────────────────────────────────────────────────────────

const C = {
  accent: "#34d399",
  dim: "#666666",
  muted: "#999999",
  text: "#e5e5e5",
  bg: "#0a0a0a",
  panel: "#141414",
  border: "#333333",
  red: "#ef4444",
  yellow: "#eab308",
  cyan: "#22d3ee",
};

// ── Metric Bar ────────────────────────────────────────────────────────────────

function MetricBar({ label, ms, maxMs = 500 }: { label: string; ms?: number; maxMs?: number }) {
  if (ms == null) return null;
  const w = Math.min(Math.max(Math.round((ms / maxMs!) * 20), 1), 20);
  return (
    <box flexDirection="row" gap={1}>
      <text fg={C.dim}>{label.padEnd(16)}</text>
      <text fg={C.cyan}>{"█".repeat(w)}{"░".repeat(20 - w)}</text>
      <text fg={C.dim}> {ms.toFixed(1)}ms</text>
    </box>
  );
}

// ── Header ────────────────────────────────────────────────────────────────────

function Header({
  connection,
  modelState,
  done,
  total,
  startTime,
}: {
  connection: ConnectionState;
  modelState: ModelState;
  done: number;
  total: number;
  startTime: number;
}) {
  const [elapsed, setElapsed] = useState("0s");

  useEffect(() => {
    const iv = setInterval(() => {
      const s = Math.floor((Date.now() - startTime) / 1000);
      const m = Math.floor(s / 60);
      setElapsed(m > 0 ? `${m}m ${s % 60}s` : `${s}s`);
    }, 1000);
    return () => clearInterval(iv);
  }, [startTime]);

  const connColor = connection === "connected" ? C.accent : connection === "connecting" ? C.yellow : C.red;
  const connLabel = connection === "connected" ? "voxd" : connection === "connecting" ? "connecting" : "disconnected";
  const modelColor = modelState === "ready" ? C.accent : modelState === "loading" ? C.yellow : C.dim;
  const modelLabel = modelState === "ready" ? "loaded" : modelState === "loading" ? "loading" : modelState === "skipped" ? "cold" : "idle";

  return (
    <box flexDirection="row" justifyContent="space-between" padding={1} height={3}>
      <box flexDirection="row" gap={1}>
        <text fg={C.accent}><strong>▲</strong></text>
        <text fg={C.text}><strong> VOX </strong></text>
        <text fg={C.dim}>transcribe-tui</text>
      </box>
      <box flexDirection="row" gap={2}>
        <text fg={C.dim}>Time <span fg={C.text}>{elapsed}</span></text>
        <text fg={connColor}>● <span fg={C.dim}>{connLabel}</span></text>
        <text fg={modelColor}>● <span fg={C.dim}>{modelLabel}</span></text>
        {total > 0 && <text fg={C.dim}>{done}/{total}</text>}
      </box>
    </box>
  );
}

// ── Transcript ────────────────────────────────────────────────────────────────

function TranscriptPane({ entry }: { entry: TranscriptionEntry | null }) {
  if (!entry) {
    return (
      <box border borderStyle="rounded" borderColor={C.border} title="Transcript" flexGrow={1} padding={1}>
        <text fg={C.dim}>No transcription yet. Drop a file path or pass files as arguments.</text>
      </box>
    );
  }

  if (entry.status === "running") {
    return (
      <box border borderStyle="rounded" borderColor={C.accent} title={`Transcribing: ${basename(entry.file)}`} flexGrow={1} padding={1}>
        <text fg={C.yellow}>⟳ Running…</text>
      </box>
    );
  }

  if (entry.status === "error") {
    return (
      <box border borderStyle="rounded" borderColor={C.red} title={`Error: ${basename(entry.file)}`} flexGrow={1} padding={1}>
        <text fg={C.red}>✗ {entry.error}</text>
      </box>
    );
  }

  if (!entry.result) return null;
  const m = entry.result.metrics;
  const rtf = m?.audioDurationMs && m?.inferenceMs ? m.audioDurationMs / m.inferenceMs : null;

  return (
    <box border borderStyle="rounded" borderColor={C.accent} title={basename(entry.file)} flexGrow={1} padding={1} flexDirection="column" gap={1}>
      <text fg={C.text}>{entry.result.text}</text>
      <box flexDirection="row" gap={3}>
        <text fg={C.dim}>model <span fg={C.text}>{entry.result.modelId}</span></text>
        {entry.wallMs != null && <text fg={C.dim}>wall <span fg={C.text}>{fmtMs(entry.wallMs)}</span></text>}
        {m?.audioDurationMs != null && <text fg={C.dim}>audio <span fg={C.text}>{fmtMs(m.audioDurationMs)}</span></text>}
        {rtf != null && <text fg={C.dim}>realtime <span fg={C.accent}><strong>{rtf.toFixed(0)}x</strong></span></text>}
      </box>
    </box>
  );
}

// ── Metrics ───────────────────────────────────────────────────────────────────

function MetricsPane({ entry }: { entry: TranscriptionEntry | null }) {
  const m = entry?.result?.metrics;
  return (
    <box border borderStyle="rounded" borderColor={m ? C.border : C.border} title="Stage Timings" padding={1} flexDirection="column">
      {m ? (
        <>
          <MetricBar label="file check" ms={m.fileCheckMs} />
          <MetricBar label="model check" ms={m.modelCheckMs} />
          <MetricBar label="model load" ms={m.modelLoadMs} maxMs={2000} />
          <MetricBar label="audio load" ms={m.audioLoadMs} />
          <MetricBar label="audio prepare" ms={m.audioPrepareMs} />
          <MetricBar label="inference" ms={m.inferenceMs} maxMs={1000} />
          <MetricBar label="total" ms={m.totalMs} maxMs={1000} />
        </>
      ) : (
        <text fg={C.dim}>Waiting for transcription…</text>
      )}
    </box>
  );
}

// ── File List ─────────────────────────────────────────────────────────────────

function FileList({ entries, selectedId }: { entries: TranscriptionEntry[]; selectedId: number | null }) {
  return (
    <box border borderStyle="rounded" borderColor={C.border} title={`Files (${entries.length})`} padding={1} flexDirection="column">
      {entries.length === 0 && <text fg={C.dim}>No files yet</text>}
      {entries.slice(-10).map((e) => {
        const sel = e.id === selectedId;
        const icon = e.status === "done" ? "✓" : e.status === "running" ? "⟳" : e.status === "error" ? "✗" : "○";
        const color = e.status === "done" ? C.accent : e.status === "error" ? C.red : e.status === "running" ? C.yellow : C.dim;
        const dur = e.result?.metrics?.audioDurationMs;

        return (
          <box key={`f-${e.id}`} flexDirection="row" gap={1}>
            <text fg={sel ? C.text : C.dim}>{sel ? "▸" : " "}</text>
            <text fg={color}>{icon}</text>
            <text fg={sel ? C.text : color}>{sel ? <strong>{basename(e.file).slice(0, 20)}</strong> : basename(e.file).slice(0, 20)}</text>
            {dur != null && <text fg={C.dim}>{fmtMs(dur)}</text>}
            {e.wallMs != null && <text fg={C.dim}>{e.wallMs.toFixed(0)}ms</text>}
          </box>
        );
      })}
    </box>
  );
}

// ── Log ───────────────────────────────────────────────────────────────────────

function LogPane({ logs }: { logs: LogEntry[] }) {
  const icons = { info: "·", ok: "✓", warn: "⚠", error: "✗" };
  const colors = { info: C.dim, ok: C.accent, warn: C.yellow, error: C.red };

  return (
    <box border borderStyle="rounded" borderColor={C.border} title="Log" padding={1} flexDirection="column" flexGrow={1}>
      {logs.length === 0 && <text fg={C.dim}>No activity yet</text>}
      {logs.slice(-8).map((log) => (
        <box key={`l-${log.id}`} flexDirection="row" gap={1}>
          <text fg={C.dim}>{log.time}</text>
          <text fg={colors[log.level]}>{icons[log.level]}</text>
          <text fg={log.level === "error" ? C.red : C.dim}>{log.message}</text>
        </box>
      ))}
    </box>
  );
}

// ── Input Bar ─────────────────────────────────────────────────────────────────

function InputBar({ value }: { value: string }) {
  return (
    <box flexDirection="row" gap={1} padding={1} height={3}>
      <text fg={C.accent}><strong>▸</strong></text>
      <text fg={C.text}>{value || " "}</text>
      <text fg={C.dim}>│ enter: transcribe · ↑↓: select · c: copy · q: quit</text>
    </box>
  );
}

// ── App ───────────────────────────────────────────────────────────────────────

function App({ initialFiles }: { initialFiles: string[] }) {
  const { width, height } = useTerminalDimensions();

  const [connection, setConnection] = useState<ConnectionState>("connecting");
  const [modelState, setModelState] = useState<ModelState>("idle");
  const [transcriptions, setTranscriptions] = useState<TranscriptionEntry[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [input, setInput] = useState("");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const startTime = useRef(Date.now()).current;

  const selectedEntry = transcriptions.find((t) => t.id === selectedId) ?? transcriptions.at(-1) ?? null;
  const done = transcriptions.filter((t) => t.status === "done").length;

  const addLog = useCallback((level: LogEntry["level"], message: string) => {
    setLogs((prev) => [...prev.slice(-50), { id: ++logId, time: ts(), level, message }]);
  }, []);

  const transcribeFile = useCallback(async (filePath: string) => {
    const abs = resolvePath(filePath);
    if (!existsSync(abs)) {
      const id = Date.now();
      setTranscriptions((prev) => [...prev, { id, file: filePath, status: "error", error: `Not found: ${abs}` }]);
      setSelectedId(id);
      addLog("error", `Not found: ${basename(filePath)}`);
      return;
    }

    const id = Date.now();
    setTranscriptions((prev) => [...prev, { id, file: abs, status: "running", startedAt: performance.now() }]);
    setSelectedId(id);
    addLog("info", `Transcribing ${basename(abs)}`);

    try {
      const result = await client.transcribeFile(abs);
      setTranscriptions((prev) =>
        prev.map((t) => {
          if (t.id !== id) return t;
          return { ...t, status: "done" as const, result, wallMs: performance.now() - (t.startedAt ?? 0) };
        }),
      );
      const rtf = result.metrics?.audioDurationMs && result.metrics?.inferenceMs
        ? ` ${(result.metrics.audioDurationMs / result.metrics.inferenceMs).toFixed(0)}x`
        : "";
      addLog("ok", `${basename(abs)} ${result.elapsedMs}ms${rtf}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setTranscriptions((prev) =>
        prev.map((t) => (t.id === id ? { ...t, status: "error" as const, error: msg } : t)),
      );
      addLog("error", `${basename(abs)}: ${msg}`);
    }
  }, [addLog]);

  // connect + load
  useEffect(() => {
    (async () => {
      addLog("info", "Connecting to voxd…");
      try {
        await client.connect();
        setConnection("connected");
        addLog("ok", "Connected");
      } catch {
        setConnection("failed");
        addLog("error", "Could not connect — run vox daemon start");
        return;
      }

      setModelState("loading");
      addLog("info", "Loading model…");
      try {
        await client.startWarmup();
        setModelState("ready");
        addLog("ok", "Model loaded");
      } catch {
        setModelState("skipped");
        addLog("warn", "Model not preloaded");
      }

      for (const f of initialFiles) {
        await transcribeFile(f);
      }
    })();
    return () => { client.disconnect(); };
  }, []);

  // handle pasted text (file drag-and-drop)
  const renderer = useRenderer();
  useEffect(() => {
    const decoder = new TextDecoder();
    const handler = (event: { bytes: Uint8Array }) => {
      const pasted = decoder.decode(event.bytes).trim();
      if (pasted) {
        const firstLine = pasted.split("\n")[0].trim();
        if (firstLine) {
          transcribeFile(firstLine);
          addLog("info", `Dropped: ${basename(resolvePath(firstLine))}`);
        }
      }
    };
    renderer.keyInput.on("paste", handler);
    return () => { renderer.keyInput.off("paste", handler); };
  }, [renderer, transcribeFile, addLog]);

  // keyboard
  useKeyboard((key) => {
    if (key.name === "escape" || (key.name === "c" && key.ctrl)) {
      process.exit(0);
    }
    if (key.name === "return") {
      const trimmed = input.trim();
      if (trimmed === "q" || trimmed === "quit") { process.exit(0); return; }
      if (trimmed) transcribeFile(trimmed);
      setInput("");
      return;
    }
    if (key.name === "backspace") {
      setInput((prev) => prev.slice(0, -1));
      return;
    }
    if (key.name === "tab") {
      setInput("");
      return;
    }
    if (key.name === "up") {
      setSelectedId((prev) => {
        const idx = transcriptions.findIndex((t) => t.id === prev);
        return idx > 0 ? transcriptions[idx - 1].id : prev;
      });
      return;
    }
    if (key.name === "down") {
      setSelectedId((prev) => {
        const idx = transcriptions.findIndex((t) => t.id === prev);
        return idx < transcriptions.length - 1 ? transcriptions[idx + 1].id : prev;
      });
      return;
    }
    if (key.name === "c" && !input) {
      const text = selectedEntry?.result?.text;
      if (text) {
        try { execSync("pbcopy", { input: text }); addLog("ok", "Copied to clipboard"); }
        catch { addLog("error", "Clipboard failed"); }
      }
      return;
    }
    // regular character input
    if (key.char && !key.ctrl && !key.alt) {
      setInput((prev) => prev + key.char);
    }
  });

  return (
    <box
      flexDirection="column"
      width={width}
      height={height}
      backgroundColor={C.bg}
    >
      {/* Header */}
      <Header
        connection={connection}
        modelState={modelState}
        done={done}
        total={transcriptions.length}
        startTime={startTime}
      />

      {/* Main content */}
      <box flexDirection="row" flexGrow={1}>
        {/* Left: transcript + metrics */}
        <box flexDirection="column" flexGrow={1}>
          <TranscriptPane entry={selectedEntry} />
          <MetricsPane entry={selectedEntry} />
        </box>

        {/* Right: files + logs */}
        <box flexDirection="column" width="35%">
          <FileList entries={transcriptions} selectedId={selectedId} />
          <LogPane logs={logs} />
        </box>
      </box>

      {/* Input */}
      <InputBar value={input} />
    </box>
  );
}

// ── Entry ─────────────────────────────────────────────────────────────────────

const files = process.argv.slice(2);
const renderer = await createCliRenderer();
createRoot(renderer).render(<App initialFiles={files} />);
