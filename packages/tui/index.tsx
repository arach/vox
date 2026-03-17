#!/usr/bin/env bun

import React, { useState, useEffect, useCallback, useRef } from "react";
import { createCliRenderer } from "@opentui/core";
import { createRoot, useKeyboard, useTerminalDimensions } from "@opentui/react";
import { VoxClient, RuntimeDiscovery, getVoxHome } from "@vox/client";
import type {
  DoctorReport,
  ModelInfo,
  TranscriptionMetrics,
  RuntimeInfo,
} from "@vox/client";
import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync } from "fs";
import { execSync } from "child_process";
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
type ActiveTab = "perf" | "health" | "config" | "voice";
type VoiceState = "idle" | "starting" | "recording" | "processing";

interface VoiceRecord {
  id: number;
  sessionId: string;
  text: string;
  elapsedMs: number;
  metrics?: TranscriptionMetrics;
  timestamp: string;
}

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
  if (Number.isFinite(n) && n < 2e9) {
    return new Date(n * 1000 + CF_EPOCH_OFFSET_MS);
  }
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

function voiceLogPath(): string {
  return join(getVoxHome(), "voice.jsonl");
}

function readVoiceLog(): VoiceRecord[] {
  const p = voiceLogPath();
  if (!existsSync(p)) return [];
  try {
    return readFileSync(p, "utf8")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .map((l, i) => ({ ...JSON.parse(l), id: i + 1 }) as VoiceRecord);
  } catch {
    return [];
  }
}

function appendVoiceLog(record: VoiceRecord): void {
  try {
    const dir = getVoxHome();
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    const { id: _, ...entry } = record;
    appendFileSync(voiceLogPath(), JSON.stringify(entry) + "\n");
  } catch { /* best effort */ }
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
  voiceState,
}: {
  connection: ConnectionState;
  tab: ActiveTab;
  runtime: RuntimeInfo | null;
  voiceState: VoiceState;
}) {
  const [uptime, setUptime] = useState("--");

  useEffect(() => {
    if (!runtime?.startedAt) return;
    const iv = setInterval(() => setUptime(fmtUptime(String(runtime.startedAt))), 1000);
    return () => clearInterval(iv);
  }, [runtime?.startedAt]);

  const connColor = connection === "connected" ? C.accent : connection === "connecting" ? C.yellow : C.red;
  const connLabel = connection === "connected" ? "connected" : connection === "connecting" ? "connecting" : "disconnected";

  const tabs: ActiveTab[] = ["perf", "health", "config", "voice"];

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
        {voiceState !== "idle" && (
          <>
            <text fg={C.dim}>│</text>
            <text fg={voiceState === "recording" ? C.red : C.yellow}>
              {voiceState === "recording" ? "● REC " : voiceState === "processing" ? "◌ processing" : "◌ starting"}
            </text>
            <Pulse active={voiceState === "recording"} />
          </>
        )}
      </box>
      <box flexDirection="row" gap={2}>
        {runtime?.version && <text fg={C.dim}>v{runtime.version}</text>}
        <text fg={C.dim}>up <span fg={C.text}>{uptime}</span></text>
        <text fg={connColor}>● <span fg={C.dim}>{connLabel}</span></text>
      </box>
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
  runtime,
}: {
  doctor: DoctorReport | null;
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

interface ConfigItem {
  section?: string;
  label: string;
  value: string;
  info?: string;
}

function ConfigPanel({
  models,
  selectedIndex,
}: {
  models: ModelInfo[];
  selectedIndex: number;
}) {
  const home = getVoxHome();
  const configPath = join(home, "providers.json");

  let providerEntries: { id: string; type: string; models: string[] }[] = [];
  if (existsSync(configPath)) {
    try {
      const config = JSON.parse(readFileSync(configPath, "utf8")) as {
        providers: { id: string; builtin?: boolean; command?: string[]; models?: string[] }[];
      };
      providerEntries = config.providers.map((p) => ({
        id: p.id,
        type: p.builtin ? "builtin" : "external",
        models: p.models ?? [],
      }));
    } catch { /* ignore */ }
  }

  const items: ConfigItem[] = [
    { section: "Client", label: "client id", value: "vox-tui", info: "this app's identity" },
    ...models.map((m, i) => ({
      section: i === 0 ? "Models" : undefined,
      label: m.id,
      value: m.preloaded ? "preloaded" : m.installed ? "installed" : m.available ? "available" : "unavailable",
      info: m.backend,
    })),
    ...(models.length === 0 ? [{ section: "Models" as string, label: "—", value: "no models registered" }] : []),
    ...providerEntries.map((e, i) => ({
      section: i === 0 ? "Providers" : undefined,
      label: e.id,
      value: e.type,
      info: e.models.length > 0 ? e.models.join(", ") : undefined,
    })),
    ...(providerEntries.length === 0 ? [{ section: "Providers" as string, label: "—", value: "using defaults" }] : []),
    { section: "Storage", label: "home", value: home },
    { label: "runtime", value: join(home, "runtime.json"), info: existsSync(join(home, "runtime.json")) ? "✓" : "—" },
    { label: "performance", value: join(home, "performance.jsonl"), info: existsSync(join(home, "performance.jsonl")) ? "✓" : "—" },
    { label: "voice log", value: join(home, "voice.jsonl"), info: existsSync(join(home, "voice.jsonl")) ? "✓" : "—" },
    { label: "providers", value: join(home, "providers.json"), info: existsSync(join(home, "providers.json")) ? "✓" : "—" },
  ];

  // Expose item count for keyboard handler
  ConfigPanel.itemCount = items.length;
  ConfigPanel.items = items;

  return (
    <box border borderStyle="rounded" borderColor={C.border} title="Configuration  ↑↓ navigate · c copy value" padding={1} flexDirection="column" flexGrow={1}>
      {items.map((item, i) => {
        const sel = i === selectedIndex;
        return (
          <React.Fragment key={`cfg-${i}`}>
            {item.section && (
              <box marginTop={i === 0 ? 0 : 1}>
                <text fg={C.muted}><strong>{item.section}</strong></text>
              </box>
            )}
            <box flexDirection="row" gap={2}>
              <text fg={sel ? C.accent : C.dim}>{sel ? "▸" : " "}</text>
              <text fg={sel ? C.text : C.dim}>{pad(item.label, 18)}</text>
              <text fg={sel ? C.text : C.text}>{pad(item.value, 30)}</text>
              {item.info && <text fg={sel ? C.accent : C.dim}>{item.info}</text>}
            </box>
          </React.Fragment>
        );
      })}
    </box>
  );
}
ConfigPanel.itemCount = 0;
ConfigPanel.items = [] as ConfigItem[];

// ── Waveform ──────────────────────────────────────────────────────────────────

const BRAILLE = [" ", "⠁", "⠃", "⠇", "⡇", "⣇", "⣧", "⣷", "⣿"];

function Pulse({ active, color = C.red }: { active: boolean; color?: string }) {
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (!active) return;
    const iv = setInterval(() => setTick((t) => t + 1), 150);
    return () => clearInterval(iv);
  }, [active]);

  if (!active) return null;

  const out = Array.from({ length: 6 }, (_, i) => {
    const v = Math.sin(tick * 0.4 + i * 0.9) * 0.4 + Math.sin(tick * 0.7 + i * 1.6) * 0.3 + 0.5;
    const n = Math.max(0, Math.min(1, v));
    return BRAILLE[Math.floor(n * (BRAILLE.length - 1))];
  }).join("");

  return <text fg={color}>{out}</text>;
}

// ── Voice Panel ───────────────────────────────────────────────────────────────

function VoicePanel({
  voiceState,
  partialText,
  history,
  selectedId,
  recordingStart,
}: {
  voiceState: VoiceState;
  partialText: string;
  history: VoiceRecord[];
  selectedId: number | null;
  recordingStart: number | null;
}) {
  const [elapsed, setElapsed] = useState("");

  useEffect(() => {
    if (!recordingStart || voiceState === "idle") {
      setElapsed("");
      return;
    }
    const iv = setInterval(() => {
      const s = Math.floor((Date.now() - recordingStart) / 1000);
      const m = Math.floor(s / 60);
      setElapsed(m > 0 ? `${m}:${String(s % 60).padStart(2, "0")}` : `0:${String(s).padStart(2, "0")}`);
    }, 200);
    return () => clearInterval(iv);
  }, [recordingStart, voiceState]);

  return (
    <box flexDirection="column" flexGrow={1}>
      {/* Session state */}
      <box border borderStyle="rounded" borderColor={voiceState === "recording" ? C.red : C.border} title="Session" padding={1} flexDirection="column">
        <box flexDirection="row" gap={2}>
          <text fg={
            voiceState === "idle" ? C.dim :
            voiceState === "recording" ? C.red :
            C.yellow
          }>
            {voiceState === "idle" ? "hold space to record" :
             voiceState === "recording" ? "● recording" :
             voiceState === "processing" ? "◌ processing..." :
             "◌ starting..."}
          </text>
          {elapsed && <text fg={C.text}>{elapsed}</text>}
        </box>
        {partialText && (
          <box marginTop={1}>
            <text fg={C.text}>{partialText}</text>
          </box>
        )}
      </box>

      {/* Transcript history */}
      <box border borderStyle="rounded" borderColor={C.border} title={`Transcripts (${history.length})  ↑↓ select · c copy`} padding={1} flexDirection="column" flexGrow={1}>
        {history.length === 0 && <text fg={C.dim}>No voice recordings yet. Hold space to record.</text>}
        {history.slice(-15).reverse().map((r) => {
          const sel = r.id === selectedId;
          return (
            <box key={`v-${r.id}`} flexDirection="column" marginBottom={1}>
              <box flexDirection="row" gap={2}>
                <text fg={sel ? C.text : C.dim}>{sel ? "▸" : " "}</text>
                <text fg={C.dim}>{r.timestamp}</text>
                <text fg={C.accent}>{fmtMs(r.elapsedMs)}</text>
                {r.metrics && (
                  <>
                    <text fg={C.cyan}>infer {fmtMs(r.metrics.inferenceMs)}</text>
                    {speedFactor(r.metrics) > 0 && (
                      <text fg={C.accent}>{speedFactor(r.metrics).toFixed(1)}x</text>
                    )}
                    <text fg={C.dim}>audio {fmtMs(r.metrics.audioDurationMs)}</text>
                  </>
                )}
              </box>
              <text fg={sel ? C.text : C.muted}>{"  "}{r.text || "(empty)"}</text>
            </box>
          );
        })}
      </box>
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

function StatusBar({ voiceState }: { voiceState: VoiceState }) {
  return (
    <box flexDirection="row" gap={1} padding={1} height={3}>
      <text fg={C.accent}><strong>▸</strong></text>
      <text fg={C.dim}>
        {voiceState === "recording"
          ? "release space to stop recording"
          : "tab: cycle · r: refresh · x: clear log · space: voice · q: quit"}
      </text>
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
  const [runtime, setRuntime] = useState<RuntimeInfo | null>(null);
  const [samples, setSamples] = useState<PerformanceSample[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);

  // Voice state
  const [voiceState, setVoiceState] = useState<VoiceState>("idle");
  const [partialText, setPartialText] = useState("");
  const [voiceHistory, setVoiceHistory] = useState<VoiceRecord[]>(() => readVoiceLog());
  const [selectedVoiceId, setSelectedVoiceId] = useState<number | null>(null);
  const [configIndex, setConfigIndex] = useState(0);
  const [recordingStart, setRecordingStart] = useState<number | null>(null);
  const sessionRef = useRef<ReturnType<typeof client.createLiveSession> | null>(null);
  const voiceSeqRef = useRef(voiceHistory.length);

  const addLog = useCallback((level: LogEntry["level"], message: string) => {
    setLogs((prev) => [...prev.slice(-50), { id: ++logSeq, time: ts(), level, message }]);
  }, []);

  const refresh = useCallback(async () => {
    if (connection !== "connected") return;

    try {
      const [m, d] = await Promise.all([
        client.listModels(),
        client.doctor(),
      ]);
      setModels(m);
      setDoctor(d);
    } catch (err) {
      addLog("error", `Refresh failed: ${err instanceof Error ? err.message : String(err)}`);
    }

    setSamples(readPerformanceSamples());
  }, [connection, addLog]);

  // ── Voice helpers ──

  const startRecording = useCallback(() => {
    if (voiceState !== "idle" || connection !== "connected") return;

    const session = client.createLiveSession();
    sessionRef.current = session;
    setVoiceState("starting");
    setPartialText("");
    setRecordingStart(Date.now());
    addLog("info", "Recording...");

    session.on("state", (e) => {
      if (e.state === "recording") setVoiceState("recording");
      else if (e.state === "processing") setVoiceState("processing");
    });

    session.on("partial", (e) => {
      setPartialText(e.text);
    });

    session.start().then(
      (final) => {
        sessionRef.current = null;
        setVoiceState("idle");
        setPartialText("");
        setRecordingStart(null);
        const record: VoiceRecord = {
          id: ++voiceSeqRef.current,
          sessionId: final.sessionId,
          text: final.text,
          elapsedMs: final.elapsedMs,
          metrics: final.metrics,
          timestamp: ts(),
        };
        appendVoiceLog(record);
        setVoiceHistory((prev) => [...prev.slice(-100), record]);
        setSelectedVoiceId(record.id);
        const preview = final.text.length > 60 ? final.text.slice(0, 60) + "..." : final.text;
        addLog("ok", `"${preview}" (${fmtMs(final.elapsedMs)})`);
      },
      (err) => {
        sessionRef.current = null;
        setVoiceState("idle");
        setPartialText("");
        setRecordingStart(null);
        addLog("error", `Voice: ${err instanceof Error ? err.message : String(err)}`);
      },
    );
  }, [voiceState, connection, addLog]);

  const stopRecording = useCallback(() => {
    if (!sessionRef.current) return;
    if (voiceState === "recording" || voiceState === "starting") {
      setVoiceState("processing");
      addLog("info", "Processing...");
      sessionRef.current.stop().catch((err) => {
        addLog("error", `Stop failed: ${err instanceof Error ? err.message : String(err)}`);
      });
    }
  }, [voiceState, addLog]);

  const cancelRecording = useCallback(() => {
    if (!sessionRef.current) return;
    sessionRef.current.cancel().catch(() => {});
    sessionRef.current = null;
    setVoiceState("idle");
    setPartialText("");
    setRecordingStart(null);
    addLog("warn", "Recording cancelled");
  }, [addLog]);

  // Connect
  useEffect(() => {
    (async () => {
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
      if (sessionRef.current) {
        sessionRef.current.cancel().catch(() => {});
      }
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

  // Keyboard — with release events for push-to-talk
  useKeyboard((key) => {
    // Quit — cancel any active session first
    if (key.name === "escape" || (key.name === "c" && key.ctrl) || key.name === "q") {
      if (voiceState !== "idle") {
        cancelRecording();
        return;
      }
      quit();
    }

    // Push-to-talk: space press = start, space release = stop
    if (key.name === "space") {
      if (key.eventType === "release") {
        stopRecording();
        return;
      }
      // Press (not repeat)
      if (!key.repeated) {
        if (voiceState === "idle") {
          startRecording();
        } else if (voiceState === "recording" || voiceState === "starting") {
          // Toggle fallback for terminals without release events
          stopRecording();
        }
      }
      return;
    }

    // Don't process other keys during recording
    if (voiceState === "recording" || voiceState === "starting") return;

    if (key.name === "tab") {
      setTab((prev) => {
        const tabs: ActiveTab[] = ["perf", "health", "config", "voice"];
        const dir = key.shift ? -1 : 1;
        return tabs[(tabs.indexOf(prev) + dir + tabs.length) % tabs.length];
      });
    }
    if (key.name === "r") {
      addLog("info", "Refreshing...");
      refresh();
    }
    if (key.name === "x") {
      if (tab === "perf") {
        // Truncate performance log
        try {
          const p = join(getVoxHome(), "performance.jsonl");
          if (existsSync(p)) {
            writeFileSync(p, "");
          }
          setSamples([]);
          addLog("ok", "Performance log cleared");
        } catch {
          addLog("error", "Failed to clear performance log");
        }
      } else {
        setLogs([]);
      }
    }
    if (key.name === "1") setTab("perf");
    if (key.name === "2") setTab("health");
    if (key.name === "3") setTab("config");
    if (key.name === "4" || key.name === "v") setTab("voice");

    // Config navigation + copy
    if (tab === "config") {
      const count = ConfigPanel.itemCount;
      if (key.name === "up") setConfigIndex((i) => Math.max(0, i - 1));
      if (key.name === "down") setConfigIndex((i) => Math.min(count - 1, i + 1));
      if (key.name === "c") {
        const item = ConfigPanel.items[configIndex];
        if (item?.value) {
          try {
            execSync("pbcopy", { input: item.value });
            addLog("ok", `Copied: ${item.value}`);
          } catch {
            addLog("error", "Clipboard failed");
          }
        }
      }
    }

    // Voice transcript navigation + copy
    if (tab === "voice" && voiceHistory.length > 0) {
      const visible = voiceHistory.slice(-15).reverse();
      if (key.name === "up") {
        setSelectedVoiceId((prev) => {
          const idx = visible.findIndex((r) => r.id === prev);
          return idx > 0 ? visible[idx - 1].id : visible[0].id;
        });
      }
      if (key.name === "down") {
        setSelectedVoiceId((prev) => {
          const idx = visible.findIndex((r) => r.id === prev);
          return idx < visible.length - 1 ? visible[idx + 1].id : prev;
        });
      }
      if (key.name === "c") {
        const entry = voiceHistory.find((r) => r.id === selectedVoiceId);
        if (entry?.text) {
          try {
            execSync("pbcopy", { input: entry.text });
            addLog("ok", "Copied to clipboard");
          } catch {
            addLog("error", "Clipboard failed");
          }
        }
      }
    }
  }, { release: true });

  return (
    <box flexDirection="column" width={width} height={height} backgroundColor={C.bg}>
      <Header connection={connection} tab={tab} runtime={runtime} voiceState={voiceState} />

      <box flexDirection="row" flexGrow={1}>
        {/* Main panel */}
        <box flexDirection="column" flexGrow={1}>
          {tab === "perf" && <PerfPanel samples={samples} />}
          {tab === "health" && (
            <HealthPanel doctor={doctor} runtime={runtime} />
          )}
          {tab === "config" && <ConfigPanel models={models} selectedIndex={configIndex} />}
          {tab === "voice" && (
            <VoicePanel
              voiceState={voiceState}
              partialText={partialText}
              history={voiceHistory}
              selectedId={selectedVoiceId}
              recordingStart={recordingStart}
            />
          )}
        </box>

        {/* Right sidebar: logs */}
        <box flexDirection="column" width="30%">
          <LogPane logs={logs} />
        </box>
      </box>

      <StatusBar voiceState={voiceState} />
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
