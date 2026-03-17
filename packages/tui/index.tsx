#!/usr/bin/env bun

import React, { useState, useEffect, useCallback, useRef } from "react";
import { createCliRenderer } from "@opentui/core";
import { createRoot, useKeyboard, useTerminalDimensions } from "@opentui/react";
import { VoxClient, RuntimeDiscovery, getVoxHome } from "@vox/client";
import type {
  DoctorReport,
  ModelInfo,
  WarmupStatus,
  TranscriptionMetrics,
  RuntimeInfo,
} from "@vox/client";
import { existsSync, readFileSync } from "fs";
import { join } from "path";

// ── Types ─────────────────────────────────────────────────────────────────────

interface PerformanceSample {
  timestamp: string;
  clientId: string;
  route: string;
  modelId: string;
  outcome: string;
  textLength: number;
  error?: string | null;
  metrics?: TranscriptionMetrics;
}

interface LogEntry {
  id: number;
  time: string;
  level: "info" | "ok" | "warn" | "error";
  message: string;
}

type ConnectionState = "connecting" | "connected" | "failed";
type ActiveTab = "perf" | "health" | "config";

// ── Helpers ───────────────────────────────────────────────────────────────────

function ts(): string {
  const d = new Date();
  return [d.getHours(), d.getMinutes(), d.getSeconds()]
    .map((n) => String(n).padStart(2, "0"))
    .join(":");
}

function fmtMs(ms: number): string {
  if (ms >= 1000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.round(ms)}ms`;
}

// Swift's JSONEncoder writes Date as seconds since 2001-01-01 (Core Foundation epoch)
const CF_EPOCH_OFFSET_MS = 978307200000;

function parseSwiftDate(value: string | number): Date {
  const n = typeof value === "string" ? Number(value) : value;
  // If it looks like a CF timestamp (< 2e9), offset from 2001 epoch
  if (Number.isFinite(n) && n < 2e9) {
    return new Date(n * 1000 + CF_EPOCH_OFFSET_MS);
  }
  // Otherwise try ISO string
  return new Date(value);
}

function fmtUptime(startedAt: string | number): string {
  const started = parseSwiftDate(startedAt);
  const s = Math.floor((Date.now() - started.getTime()) / 1000);
  if (s < 0 || !Number.isFinite(s)) return "--";
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

function speedFactor(m: TranscriptionMetrics): number {
  if (m.realtimeFactor > 0 && Number.isFinite(m.realtimeFactor)) return 1 / m.realtimeFactor;
  if (m.audioDurationMs > 0 && m.inferenceMs > 0) return m.audioDurationMs / m.inferenceMs;
  return 0;
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  return sorted[Math.floor(sorted.length * p)] ?? sorted[sorted.length - 1];
}

function readPerformanceSamples(): PerformanceSample[] {
  const logPath = join(getVoxHome(), "performance.jsonl");
  if (!existsSync(logPath)) return [];
  try {
    return readFileSync(logPath, "utf8")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .map((l) => JSON.parse(l) as PerformanceSample);
  } catch {
    return [];
  }
}

let logSeq = 0;
const client = new VoxClient({ clientId: "vox-tui" });

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
  blue: "#60a5fa",
};

// ── Header ────────────────────────────────────────────────────────────────────

function Header({
  connection,
  tab,
  runtime,
}: {
  connection: ConnectionState;
  tab: ActiveTab;
  runtime: RuntimeInfo | null;
}) {
  const [uptime, setUptime] = useState("--");

  useEffect(() => {
    if (!runtime?.startedAt) return;
    const iv = setInterval(() => setUptime(fmtUptime(String(runtime.startedAt))), 1000);
    return () => clearInterval(iv);
  }, [runtime?.startedAt]);

  const connColor = connection === "connected" ? C.accent : connection === "connecting" ? C.yellow : C.red;
  const connLabel = connection === "connected" ? "connected" : connection === "connecting" ? "connecting" : "disconnected";

  const tabs: ActiveTab[] = ["perf", "health", "config"];

  return (
    <box flexDirection="row" justifyContent="space-between" padding={1} height={3}>
      <box flexDirection="row" gap={1}>
        <text fg={C.accent}><strong>▲</strong></text>
        <text fg={C.text}><strong> VOX </strong></text>
        <text fg={C.dim}>dashboard</text>
        <text fg={C.dim}>│</text>
        {tabs.map((t) => (
          <text key={t} fg={t === tab ? C.text : C.dim}>
            {t === tab ? <strong>{` ${t} `}</strong> : ` ${t} `}
          </text>
        ))}
      </box>
      <box flexDirection="row" gap={2}>
        <text fg={C.dim}>up <span fg={C.text}>{uptime}</span></text>
        <text fg={connColor}>● <span fg={C.dim}>{connLabel}</span></text>
      </box>
    </box>
  );
}

// ── Models Panel ──────────────────────────────────────────────────────────────

function ModelsPanel({ models }: { models: ModelInfo[] }) {
  return (
    <box border borderStyle="rounded" borderColor={C.border} title={`Models (${models.length})`} padding={1} flexDirection="column" flexGrow={1}>
      {models.length === 0 && <text fg={C.dim}>No models loaded</text>}
      {/* Header */}
      {models.length > 0 && (
        <box flexDirection="row" gap={2}>
          <text fg={C.dim}>{" "}</text>
          <text fg={C.dim}>{pad("id", 24)}</text>
          <text fg={C.dim}>{pad("backend", 14)}</text>
          <text fg={C.dim}>status</text>
        </box>
      )}
      {models.map((m) => {
        const icon = m.preloaded ? "◆" : m.installed ? "◇" : m.available ? "○" : "✗";
        const iconColor = m.preloaded ? C.accent : m.installed ? C.cyan : m.available ? C.dim : C.red;
        const status = m.preloaded
          ? "preloaded"
          : m.installed
            ? "installed"
            : m.available
              ? "available"
              : "unavailable";
        const statusColor = m.preloaded ? C.accent : m.installed ? C.cyan : m.available ? C.yellow : C.red;

        return (
          <box key={m.id} flexDirection="row" gap={2}>
            <text fg={iconColor}>{icon}</text>
            <text fg={C.text}>{pad(m.id, 24)}</text>
            <text fg={C.dim}>{pad(m.backend, 14)}</text>
            <text fg={statusColor}>{status}</text>
          </box>
        );
      })}
    </box>
  );
}

// ── Performance Panel ─────────────────────────────────────────────────────────

function PerfPanel({ samples }: { samples: PerformanceSample[] }) {
  const successes = samples.filter((s) => s.outcome === "ok" && s.metrics);
  const metrics = successes.map((s) => s.metrics!);
  const clients = [...new Set(samples.map((s) => s.clientId))].sort();
  const models = [...new Set(samples.map((s) => s.modelId))].sort();

  const totalSorted = [...metrics.map((m) => m.totalMs)].sort((a, b) => a - b);
  const inferSorted = [...metrics.map((m) => m.inferenceMs)].sort((a, b) => a - b);
  const speedSorted = [...metrics.map(speedFactor).filter((v) => v > 0)].sort((a, b) => a - b);

  const avg = (arr: number[]) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

  return (
    <box flexDirection="column" flexGrow={1}>
      {/* Summary */}
      <box border borderStyle="rounded" borderColor={C.border} title={`Performance (${samples.length} samples)`} padding={1} flexDirection="column">
        {successes.length === 0 ? (
          <text fg={C.dim}>No successful transcriptions recorded yet</text>
        ) : (
          <>
            <box flexDirection="row" gap={2}>
              <text fg={C.dim}>{pad("", 11)}</text>
              <text fg={C.dim}>{pad("avg", 12)}</text>
              <text fg={C.dim}>{pad("p50", 12)}</text>
              <text fg={C.dim}>{pad("p95", 12)}</text>
              <text fg={C.dim}>{pad("min", 12)}</text>
              <text fg={C.dim}>max</text>
            </box>
            <StatRow label="total" values={totalSorted} format={fmtMs} />
            <StatRow label="inference" values={inferSorted} format={fmtMs} />
            {speedSorted.length > 0 && (
              <StatRow label="speed" values={speedSorted} format={(v) => `${v.toFixed(1)}x`} />
            )}
            <box flexDirection="row" gap={2} marginTop={1}>
              <text fg={C.dim}>clients <span fg={C.text}>{clients.length}</span></text>
              <text fg={C.dim}>models <span fg={C.text}>{models.join(", ")}</span></text>
              <text fg={C.dim}>errors <span fg={samples.filter((s) => s.outcome !== "ok").length > 0 ? C.red : C.text}>{samples.filter((s) => s.outcome !== "ok").length}</span></text>
            </box>
          </>
        )}
      </box>

      {/* By Client */}
      {successes.length > 0 && clients.length > 0 && (
        <box border borderStyle="rounded" borderColor={C.border} title="By Client" padding={1} flexDirection="column">
          <box flexDirection="row" gap={2}>
            <text fg={C.dim}>{pad("client", 20)}</text>
            <text fg={C.dim}>{pad("calls", 8)}</text>
            <text fg={C.dim}>{pad("p50", 12)}</text>
            <text fg={C.dim}>{pad("infer", 12)}</text>
            <text fg={C.dim}>speed</text>
          </box>
          {clients.map((cid) => {
            const cm = successes.filter((s) => s.clientId === cid).map((s) => s.metrics!);
            if (cm.length === 0) return null;
            const ts = [...cm.map((m) => m.totalMs)].sort((a, b) => a - b);
            const is_ = [...cm.map((m) => m.inferenceMs)].sort((a, b) => a - b);
            const sp = [...cm.map(speedFactor).filter((v) => v > 0)].sort((a, b) => a - b);
            return (
              <box key={cid} flexDirection="row" gap={2}>
                <text fg={C.text}>{pad(cid, 20)}</text>
                <text fg={C.dim}>{pad(String(cm.length), 8)}</text>
                <text fg={C.cyan}>{pad(fmtMs(percentile(ts, 0.5)), 12)}</text>
                <text fg={C.cyan}>{pad(fmtMs(percentile(is_, 0.5)), 12)}</text>
                <text fg={C.accent}>{sp.length ? `${avg(sp).toFixed(1)}x` : "--"}</text>
              </box>
            );
          })}
        </box>
      )}

      {/* Recent */}
      <box border borderStyle="rounded" borderColor={C.border} title="Recent" padding={1} flexDirection="column" flexGrow={1}>
        {samples.length === 0 && <text fg={C.dim}>No samples yet</text>}
        {samples.slice(-12).reverse().map((s, i) => {
          const stamp = s.timestamp.replace("T", " ").replace(/\.\d+Z$/, "");
          const short = stamp.slice(11, 19);
          if (s.outcome !== "ok" || !s.metrics) {
            return (
              <box key={`r-${i}`} flexDirection="row" gap={2}>
                <text fg={C.dim}>{short}</text>
                <text fg={C.red}>✗</text>
                <text fg={C.dim}>{pad(s.clientId, 18)}</text>
                <text fg={C.red}>{(s.error ?? "error").slice(0, 40)}</text>
              </box>
            );
          }
          const sp = speedFactor(s.metrics);
          return (
            <box key={`r-${i}`} flexDirection="row" gap={2}>
              <text fg={C.dim}>{short}</text>
              <text fg={C.accent}>✓</text>
              <text fg={C.dim}>{pad(s.clientId, 18)}</text>
              <text fg={C.text}>{pad(fmtMs(s.metrics.totalMs), 10)}</text>
              <text fg={C.cyan}>{pad(fmtMs(s.metrics.inferenceMs), 10)}</text>
              <text fg={sp > 0 ? C.accent : C.dim}>{pad(sp > 0 ? `${sp.toFixed(1)}x` : "--", 8)}</text>
              <text fg={C.dim}>{s.modelId}</text>
            </box>
          );
        })}
      </box>
    </box>
  );
}

function StatRow({
  label,
  values,
  format,
}: {
  label: string;
  values: number[];
  format: (v: number) => string;
}) {
  if (values.length === 0) return null;
  const avg = values.reduce((a, b) => a + b, 0) / values.length;
  return (
    <box flexDirection="row" gap={2}>
      <text fg={C.dim}>{pad(label, 11)}</text>
      <text fg={C.text}>{pad(format(avg), 12)}</text>
      <text fg={C.cyan}>{pad(format(percentile(values, 0.5)), 12)}</text>
      <text fg={C.yellow}>{pad(format(percentile(values, 0.95)), 12)}</text>
      <text fg={C.dim}>{pad(format(values[0]), 12)}</text>
      <text fg={C.dim}>{format(values[values.length - 1])}</text>
    </box>
  );
}

// ── Health Panel ──────────────────────────────────────────────────────────────

function HealthPanel({
  doctor,
  warmup,
  runtime,
}: {
  doctor: DoctorReport | null;
  warmup: WarmupStatus | null;
  runtime: RuntimeInfo | null;
}) {
  return (
    <box flexDirection="column" flexGrow={1}>
      {/* Doctor Checks */}
      <box border borderStyle="rounded" borderColor={C.border} title="Doctor" padding={1} flexDirection="column">
        {!doctor && <text fg={C.dim}>Loading...</text>}
        {doctor?.checks.map((check) => {
          const icon = check.status === "ok" ? "✓" : check.status === "warning" ? "⚠" : "✗";
          const color = check.status === "ok" ? C.accent : check.status === "warning" ? C.yellow : C.red;
          return (
            <box key={check.name} flexDirection="row" gap={1}>
              <text fg={color}>{icon}</text>
              <text fg={C.text}>{pad(check.name, 14)}</text>
              <text fg={C.dim}>{check.detail}</text>
            </box>
          );
        })}
        {doctor && (
          <box marginTop={1}>
            <text fg={doctor.ready ? C.accent : C.red}>
              {doctor.ready ? "System ready" : "System not ready"}
            </text>
          </box>
        )}
      </box>

      {/* Warmup */}
      <box border borderStyle="rounded" borderColor={C.border} title="Warmup" padding={1} flexDirection="column">
        {!warmup && <text fg={C.dim}>Loading...</text>}
        {warmup && (
          <>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>model</text>
              <text fg={C.text}>{warmup.modelId}</text>
            </box>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>state</text>
              <text fg={warmup.state === "ready" ? C.accent : warmup.state === "warming" ? C.yellow : warmup.state === "failed" ? C.red : C.dim}>
                {warmup.state}
              </text>
            </box>
            {warmup.requestedBy && (
              <box flexDirection="row" gap={1}>
                <text fg={C.dim}>client</text>
                <text fg={C.text}>{warmup.requestedBy}</text>
              </box>
            )}
            {warmup.lastError && (
              <box flexDirection="row" gap={1}>
                <text fg={C.dim}>error</text>
                <text fg={C.red}>{warmup.lastError}</text>
              </box>
            )}
          </>
        )}
      </box>

      {/* Daemon Info */}
      <box border borderStyle="rounded" borderColor={C.border} title="Daemon" padding={1} flexDirection="column">
        {!runtime && <text fg={C.dim}>Loading...</text>}
        {runtime && (
          <>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>version</text>
              <text fg={C.text}>{runtime.version}</text>
            </box>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>pid</text>
              <text fg={C.text}>{runtime.pid}</text>
            </box>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>port</text>
              <text fg={C.text}>{runtime.port}</text>
            </box>
            <box flexDirection="row" gap={1}>
              <text fg={C.dim}>started</text>
              <text fg={C.text}>{parseSwiftDate(runtime.startedAt).toLocaleString()}</text>
            </box>
          </>
        )}
      </box>

    </box>
  );
}

// ── Config Panel ──────────────────────────────────────────────────────────────

function ConfigPanel({ models }: { models: ModelInfo[] }) {
  return (
    <box flexDirection="column" flexGrow={1}>
      <ModelsPanel models={models} />
      <ProvidersConfigPanel />
    </box>
  );
}

function ProvidersConfigPanel() {
  const configPath = join(getVoxHome(), "providers.json");
  let entries: { id: string; type: string; models: string[] }[] = [];

  if (existsSync(configPath)) {
    try {
      const config = JSON.parse(readFileSync(configPath, "utf8")) as {
        providers: { id: string; builtin?: boolean; command?: string[]; models?: string[] }[];
      };
      entries = config.providers.map((p) => ({
        id: p.id,
        type: p.builtin ? "builtin" : "external",
        models: p.models ?? [],
      }));
    } catch { /* ignore */ }
  }

  return (
    <box border borderStyle="rounded" borderColor={C.border} title="Providers" padding={1} flexDirection="column" flexGrow={1}>
      {entries.length === 0 && <text fg={C.dim}>No providers.json (using defaults)</text>}
      {entries.map((e) => (
        <box key={e.id} flexDirection="row" gap={1}>
          <text fg={e.type === "builtin" ? C.accent : C.blue}>
            {e.type === "builtin" ? "●" : "◉"}
          </text>
          <text fg={C.text}>{pad(e.id, 16)}</text>
          <text fg={C.dim}>{e.type === "builtin" ? "builtin" : "external"}</text>
          {e.models.length > 0 && <text fg={C.dim}>→ {e.models.join(", ")}</text>}
        </box>
      ))}
    </box>
  );
}

// ── Log Panel ─────────────────────────────────────────────────────────────────

function LogPane({ logs }: { logs: LogEntry[] }) {
  const icons = { info: "·", ok: "✓", warn: "⚠", error: "✗" };
  const colors = { info: C.dim, ok: C.accent, warn: C.yellow, error: C.red };

  return (
    <box border borderStyle="rounded" borderColor={C.border} title="Activity" padding={1} flexDirection="column">
      {logs.length === 0 && <text fg={C.dim}>No activity yet</text>}
      {logs.slice(-10).map((log) => (
        <box key={`l-${log.id}`} flexDirection="row" gap={1}>
          <text fg={C.dim}>{log.time}</text>
          <text fg={colors[log.level]}>{icons[log.level]}</text>
          <text fg={log.level === "error" ? C.red : C.dim}>{log.message}</text>
        </box>
      ))}
    </box>
  );
}

// ── Status Bar ────────────────────────────────────────────────────────────────

function StatusBar({ tab }: { tab: ActiveTab }) {
  return (
    <box flexDirection="row" gap={1} padding={1} height={3}>
      <text fg={C.accent}><strong>▸</strong></text>
      <text fg={C.dim}>tab: cycle panels · r: refresh · w: warmup · q: quit</text>
    </box>
  );
}

// ── Pad helper ────────────────────────────────────────────────────────────────

function pad(s: string, width: number): string {
  const padding = Math.max(width - s.length, 0);
  return s + " ".repeat(padding);
}

// ── App ───────────────────────────────────────────────────────────────────────

function App() {
  const { width, height } = useTerminalDimensions();

  const [connection, setConnection] = useState<ConnectionState>("connecting");
  const [tab, setTab] = useState<ActiveTab>("perf");
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [doctor, setDoctor] = useState<DoctorReport | null>(null);
  const [warmup, setWarmup] = useState<WarmupStatus | null>(null);
  const [runtime, setRuntime] = useState<RuntimeInfo | null>(null);
  const [samples, setSamples] = useState<PerformanceSample[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);

  const addLog = useCallback((level: LogEntry["level"], message: string) => {
    setLogs((prev) => [...prev.slice(-50), { id: ++logSeq, time: ts(), level, message }]);
  }, []);

  const refresh = useCallback(async () => {
    if (connection !== "connected") return;

    try {
      const [m, d, w] = await Promise.all([
        client.listModels(),
        client.doctor(),
        client.getWarmupStatus(),
      ]);
      setModels(m);
      setDoctor(d);
      setWarmup(w);
    } catch (err) {
      addLog("error", `Refresh failed: ${err instanceof Error ? err.message : String(err)}`);
    }

    setSamples(readPerformanceSamples());
  }, [connection, addLog]);

  // Connect
  useEffect(() => {
    (async () => {
      // Read runtime info
      const disc = new RuntimeDiscovery();
      const rt = disc.read();
      setRuntime(rt);

      addLog("info", "Connecting to voxd...");
      try {
        await client.connect();
        setConnection("connected");
        addLog("ok", "Connected");
      } catch {
        setConnection("failed");
        addLog("error", "Could not connect — run vox daemon start");
      }
    })();
    return () => {
      client.disconnect();
    };
  }, []);

  // Initial + periodic refresh
  useEffect(() => {
    if (connection !== "connected") return;

    refresh();
    const iv = setInterval(refresh, 5000);
    return () => clearInterval(iv);
  }, [connection, refresh]);

  // Keyboard — OpenTUI uses key.name for all keys (no key.char)
  useKeyboard((key) => {
    if (key.name === "escape" || (key.name === "c" && key.ctrl) || key.name === "q") {
      quit();
    }
    if (key.name === "tab") {
      setTab((prev) => {
        const tabs: ActiveTab[] = ["perf", "health", "config"];
        return tabs[(tabs.indexOf(prev) + 1) % tabs.length];
      });
    }
    if (key.name === "r") {
      addLog("info", "Refreshing...");
      refresh();
    }
    if (key.name === "w") {
      if (connection === "connected") {
        addLog("info", "Starting warmup...");
        client.startWarmup().then(
          (s) => {
            setWarmup(s);
            addLog("ok", `Warmup: ${s.state}`);
          },
          (err) => addLog("error", `Warmup failed: ${err instanceof Error ? err.message : String(err)}`),
        );
      }
    }
    if (key.name === "1") setTab("perf");
    if (key.name === "2") setTab("health");
    if (key.name === "3") setTab("config");
  });

  return (
    <box flexDirection="column" width={width} height={height} backgroundColor={C.bg}>
      <Header connection={connection} tab={tab} runtime={runtime} />

      <box flexDirection="row" flexGrow={1}>
        {/* Main panel */}
        <box flexDirection="column" flexGrow={1}>
          {tab === "perf" && <PerfPanel samples={samples} />}
          {tab === "health" && (
            <HealthPanel doctor={doctor} warmup={warmup} runtime={runtime} />
          )}
          {tab === "config" && <ConfigPanel models={models} />}
        </box>

        {/* Right sidebar: logs */}
        <box flexDirection="column" width="30%">
          <LogPane logs={logs} />
        </box>
      </box>

      <StatusBar tab={tab} />
    </box>
  );
}

// ── Entry ─────────────────────────────────────────────────────────────────────

const renderer = await createCliRenderer();

function quit() {
  client.disconnect();
  renderer.destroy();
}

createRoot(renderer).render(<App />);
