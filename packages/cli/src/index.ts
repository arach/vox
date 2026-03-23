#!/usr/bin/env bun

import { existsSync, readFileSync, rmSync } from "fs";
import { join, resolve } from "path";
import { createInterface } from "readline";
import {
  getVoxHome,
  RuntimeDiscovery,
  getRuntimeFilePath,
  VoxClient,
  type DoctorReport,
  type FileTranscriptionResult,
  type ModelInfo,
  type RuntimeInfo,
  type TranscriptionMetrics,
  type WarmupStatus,
  type WordTiming,
} from "@vox/client";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SWIFT_ROOT = join(REPO_ROOT, "swift");
const DAEMON_BINARY = join(SWIFT_ROOT, ".build", "debug", "voxd");

async function main(argv: string[]): Promise<void> {
  const [command, subcommand, ...rest] = argv;

  switch (command) {
    case "daemon":
      await handleDaemon(subcommand, rest);
      return;
    case "doctor":
      await withClient(async (client) => {
        const report = await client.doctor();
        printDoctorReport(report);
      });
      return;
    case "models":
      await handleModels(subcommand, rest);
      return;
    case "warmup":
      await handleWarmup(subcommand, rest);
      return;
    case "perf":
      await handlePerf(subcommand, rest);
      return;
    case "logs":
      handleLogs(subcommand, rest);
      return;
    case "transcribe":
      await handleTranscribe(subcommand, rest);
      return;
    case "tui":
      launchTui();
      return;
    case "help":
    case undefined:
      printUsage();
      return;
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}

async function handleDaemon(subcommand: string | undefined, rest: string[]): Promise<void> {
  switch (subcommand) {
    case "start":
      await ensureDaemonRunning();
      console.log("Vox daemon is running.");
      return;
    case "stop":
      await stopDaemon();
      console.log("Vox daemon stopped.");
      return;
    case "status":
      printDaemonStatus();
      return;
    default:
      throw new Error(`Unknown daemon command: ${subcommand ?? "(missing)"}`);
  }
}

async function handleModels(subcommand: string | undefined, rest: string[]): Promise<void> {
  const modelId = rest[0] ?? "parakeet:v3";

  await withClient(async (client) => {
    switch (subcommand) {
      case "list": {
        const models = await client.listModels();
        printModels(models);
        return;
      }
      case "install": {
        const model = await client.installModel(modelId, (event) => {
          console.error(`${event.modelId} ${(event.progress * 100).toFixed(0)}% ${event.status}`);
        });
        console.log(`Installed ${model.id}`);
        return;
      }
      case "preload": {
        const model = await client.preloadModel(modelId, (event) => {
          console.error(`${event.modelId} ${(event.progress * 100).toFixed(0)}% ${event.status}`);
        });
        console.log(`Preloaded ${model.id}`);
        return;
      }
      default:
        throw new Error(`Unknown models command: ${subcommand ?? "(missing)"}`);
    }
  });
}

async function handleTranscribe(subcommand: string | undefined, rest: string[]): Promise<void> {
  switch (subcommand) {
    case "file": {
      const showMetrics = rest.includes("--metrics");
      const showTimestamps = rest.includes("--timestamps");
      const filePath = rest.find((value) => !value.startsWith("--"));
      if (!filePath) {
        throw new Error("Usage: vox transcribe file [--metrics] [--timestamps] <path>");
      }
      await withClient(async (client) => {
        const result = await client.transcribeFile(resolve(process.cwd(), filePath));
        console.log(result.text);
        if (showMetrics && result.metrics) {
          printTranscriptionMetrics(result.metrics);
        }
        if (showTimestamps) {
          printWordTimings(result.words);
        }
      });
      return;
    }
    case "bench": {
      const filePath = rest[0];
      const runs = Number(rest[1] ?? 5);
      if (!filePath) {
        throw new Error("Usage: vox transcribe bench <path> [runs]");
      }
      if (!Number.isInteger(runs) || runs < 1) {
        throw new Error(`Expected a positive integer run count, received: ${rest[1] ?? "(missing)"}`);
      }

      await withClient(async (client) => {
        await client.preloadModel();
        const results: FileTranscriptionResult[] = [];

        for (let index = 0; index < runs; index += 1) {
          const result = await client.transcribeFile(resolve(process.cwd(), filePath));
          results.push(result);

          const metrics = result.metrics;
          if (!metrics) {
            console.log(`run ${index + 1}: total=${result.elapsedMs}ms`);
            continue;
          }

          console.log(
            `run ${index + 1}: total=${formatMs(metrics.totalMs)} inference=${formatMs(metrics.inferenceMs)} audio=${formatMs(metrics.audioDurationMs)} rtf=${formatSpeed(metrics.realtimeFactor)}`,
          );
        }

        printBenchmarkSummary(results);
      });
      return;
    }
    case "live": {
      const showTimestamps = rest.includes("--timestamps");
      await withClient(async (client) => {
        const session = client.createLiveSession();
        session.on("state", ({ state }) => {
          console.error(`state: ${state}`);
        });
        session.on("partial", ({ text }) => {
          console.error(`partial: ${text}`);
        });
        session.on("final", ({ text, words }) => {
          console.log(text);
          if (showTimestamps) {
            printWordTimings(words);
          }
        });

        const transcriptPromise = session.start();
        console.error("Recording. Press Enter to stop.");
        await waitForEnter();
        await session.stop();
        await transcriptPromise;
      });
      return;
    }
    case "status": {
      await withClient(async (client) => {
        printLiveSessionStatus(await client.getLiveSessionStatus());
      });
      return;
    }
    case "cancel": {
      const sessionId = rest.find((value) => !value.startsWith("--"));
      await withClient(async (client) => {
        const result = await client.cancelLiveSession(sessionId);
        console.log(`cancelled: ${result.cancelled}`);
        console.log(`session: ${result.sessionId}`);
      });
      return;
    }
    default:
      throw new Error(`Unknown transcribe command: ${subcommand ?? "(missing)"}`);
  }
}

async function handleWarmup(subcommand: string | undefined, rest: string[]): Promise<void> {
  const modelId = rest.find((value) => !value.startsWith("--") && Number.isNaN(Number(value))) ?? "parakeet:v3";

  await withClient(async (client) => {
    switch (subcommand) {
      case "status": {
        printWarmupStatus(await client.getWarmupStatus(modelId));
        return;
      }
      case "start": {
        printWarmupStatus(await client.startWarmup(modelId));
        return;
      }
      case "schedule": {
        const delayMs = Number(rest.find((value) => /^\d+$/.test(value)) ?? 0);
        printWarmupStatus(await client.scheduleWarmup(modelId, delayMs));
        return;
      }
      default:
        throw new Error(`Unknown warmup command: ${subcommand ?? "(missing)"}`);
    }
  });
}

async function handlePerf(subcommand: string | undefined, rest: string[]): Promise<void> {
  switch (subcommand) {
    case "dashboard":
    case undefined: {
      printPerformanceDashboard(rest);
      return;
    }
    default:
      throw new Error(`Unknown perf command: ${subcommand}`);
  }
}

function handleLogs(subcommand: string | undefined, rest: string[]): void {
  const args = subcommand?.startsWith("--") ? [subcommand, ...rest] : rest;
  const tail = Number(readOption(args, "--tail") ?? 80);
  if (!Number.isInteger(tail) || tail < 1) {
    throw new Error(`Expected a positive integer tail count, received: ${readOption(args, "--tail") ?? "(missing)"}`);
  }

  const target = !subcommand || subcommand.startsWith("--") ? "daemon" : subcommand;
  const path = resolveLogPath(target);
  if (!existsSync(path)) {
    console.log(`No log at ${path}`);
    return;
  }

  console.log(`log: ${path}`);
  const content = readFileSync(path, "utf8");
  const lines = content.split("\n").filter(Boolean);
  for (const line of lines.slice(-tail)) {
    console.log(line);
  }
}

async function withClient<T>(fn: (client: VoxClient) => Promise<T>): Promise<T> {
  await ensureDaemonRunning();
  const client = new VoxClient({ clientId: "vox-cli" });
  await client.connect();
  try {
    return await fn(client);
  } finally {
    client.disconnect();
  }
}

async function ensureDaemonRunning(): Promise<RuntimeInfo> {
  const existing = readRuntimeInfo();
  if (existing) {
    const listenerPid = findListeningPid(existing.port);
    if (listenerPid && processIsRunning(listenerPid)) {
      return listenerPid === existing.pid ? existing : { ...existing, pid: listenerPid };
    }
  }

  buildDaemon();
  const proc = Bun.spawn([DAEMON_BINARY], {
    cwd: REPO_ROOT,
    detached: true,
    stdout: "ignore",
    stderr: "ignore",
  });
  proc.unref?.();

  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const runtime = readRuntimeInfo();
    if (runtime) {
      const listenerPid = findListeningPid(runtime.port);
      if (listenerPid && processIsRunning(listenerPid)) {
        return listenerPid === runtime.pid ? runtime : { ...runtime, pid: listenerPid };
      }
    }
    await Bun.sleep(200);
  }

  throw new Error(`Timed out waiting for Vox daemon. Expected runtime file at ${getRuntimeFilePath()}`);
}

function buildDaemon(): void {
  if (existsSync(DAEMON_BINARY)) {
    return;
  }

  const result = Bun.spawnSync(["swift", "build", "--package-path", SWIFT_ROOT, "--product", "voxd"], {
    cwd: REPO_ROOT,
    stdout: "inherit",
    stderr: "inherit",
  });

  if (result.exitCode !== 0) {
    throw new Error("Failed to build voxd.");
  }
}

async function stopDaemon(): Promise<void> {
  const runtime = readRuntimeInfo();
  const port = runtime?.port ?? 42137;
  const pids = new Set<number>();

  if (runtime && processIsRunning(runtime.pid)) {
    pids.add(runtime.pid);
  }
  const listenerPid = findListeningPid(port);
  if (listenerPid && processIsRunning(listenerPid)) {
    pids.add(listenerPid);
  }

  if (pids.size === 0) {
    rmSync(getRuntimeFilePath(), { force: true });
    return;
  }

  for (const pid of pids) {
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // Ignore already-exited processes.
    }
  }
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const activePid = findListeningPid(port);
    const anyRunning = [...pids].some((pid) => processIsRunning(pid));
    if (!activePid && !anyRunning) {
      rmSync(getRuntimeFilePath(), { force: true });
      return;
    }
    await Bun.sleep(100);
  }
}

function printDaemonStatus(): void {
  const runtime = readRuntimeInfo();
  const port = runtime?.port ?? 42137;
  const listenerPid = findListeningPid(port);
  if (!runtime && !listenerPid) {
    console.log("Vox daemon is not running.");
    return;
  }

  const runtimeRunning = runtime ? processIsRunning(runtime.pid) : false;
  const status = listenerPid
    ? "running"
    : runtimeRunning
      ? "detached"
      : "stale";

  console.log(`status: ${status}`);
  if (listenerPid) {
    console.log(`pid: ${listenerPid}`);
  } else if (runtime) {
    console.log(`pid: ${runtime.pid}`);
  }
  console.log(`port: ${port}`);
  if (runtime && listenerPid && runtime.pid !== listenerPid) {
    console.log(`runtime pid: ${runtime.pid}`);
    console.log("warning: runtime.json does not match the process holding the port");
  }
  console.log(`runtime: ${getRuntimeFilePath()}`);
}

function printDoctorReport(report: DoctorReport): void {
  console.log(`ready: ${report.ready}`);
  for (const check of report.checks) {
    console.log(`${check.status.padEnd(7)} ${check.name} ${check.detail}`);
  }
}

function printModels(models: ModelInfo[]): void {
  for (const model of models) {
    console.log(
      `${model.id} installed=${model.installed} preloaded=${model.preloaded} available=${model.available}`,
    );
  }
}

function printWarmupStatus(status: WarmupStatus): void {
  console.log(`model: ${status.modelId}`);
  console.log(`state: ${status.state}`);
  if (status.requestedBy) {
    console.log(`client: ${status.requestedBy}`);
  }
  if (status.scheduledFor) {
    console.log(`scheduled: ${status.scheduledFor}`);
  }
  if (status.startedAt) {
    console.log(`started: ${status.startedAt}`);
  }
  if (status.completedAt) {
    console.log(`completed: ${status.completedAt}`);
  }
  if (status.lastError) {
    console.log(`error: ${status.lastError}`);
  }
}

function printLiveSessionStatus(status: Awaited<ReturnType<VoxClient["getLiveSessionStatus"]>>): void {
  if (!status) {
    console.log("active: no");
    return;
  }

  console.log("active: yes");
  console.log(`session: ${status.sessionId}`);
  console.log(`client: ${status.clientId}`);
  console.log(`model: ${status.modelId}`);
  console.log(`state: ${status.state}`);
  console.log(`started: ${status.startedAt}`);
}

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

function printPerformanceDashboard(args: string[]): void {
  const clientFilter = readOption(args, "--client");
  const routeFilter = readOption(args, "--route");
  const last = Number(readOption(args, "--last") ?? 20);
  const logPath = join(getVoxHome(), "performance.jsonl");

  if (!existsSync(logPath)) {
    console.log(`No performance log at ${logPath}`);
    return;
  }

  const samples = readPerformanceSamples(logPath)
    .filter((sample) => !clientFilter || sample.clientId === clientFilter)
    .filter((sample) => !routeFilter || sample.route === routeFilter);

  if (samples.length === 0) {
    console.log("No matching performance samples.");
    return;
  }

  const successes = samples.filter((sample) => sample.outcome === "ok" && sample.metrics);
  const clients = [...new Set(samples.map((sample) => sample.clientId))].sort();
  const routes = [...new Set(samples.map((sample) => sample.route))].sort();

  console.log("Vox Performance Dashboard");
  console.log(`log: ${logPath}`);
  console.log(`samples: ${samples.length}  success: ${successes.length}  clients: ${clients.length}  routes: ${routes.join(", ")}`);
  console.log("");

  if (successes.length > 0) {
    const metrics = successes.map((sample) => sample.metrics!).filter(Boolean);
    console.log("Overall");
    console.log(`  total:     ${formatStat(computeStats(metrics.map((value) => value.totalMs)), formatMs)}`);
    console.log(`  inference: ${formatStat(computeStats(metrics.map((value) => value.inferenceMs)), formatMs)}`);
    const speedValues = metrics.map(getSpeedFactor).filter((value) => value > 0);
    if (speedValues.length > 0) {
      console.log(`  speed:     ${formatStat(computeStats(speedValues), formatSpeedFactor)}`);
    }
    console.log("");
  }

  console.log("By Client");
  console.log(`  ${pad("client", 18)} ${pad("calls", 5, true)} ${pad("p50 total", 10, true)} ${pad("p50 infer", 10, true)} ${pad("avg speed", 11, true)}`);
  for (const clientId of clients) {
    const clientSamples = successes.filter((sample) => sample.clientId === clientId).map((sample) => sample.metrics!);
    if (clientSamples.length === 0) {
      continue;
    }
    const totalStats = computeStats(clientSamples.map((value) => value.totalMs));
    const inferStats = computeStats(clientSamples.map((value) => value.inferenceMs));
    const speedStats = computeStats(clientSamples.map(getSpeedFactor).filter((value) => value > 0));
    console.log(
      `  ${pad(clientId, 18)} ${pad(String(clientSamples.length), 5, true)} ${pad(formatMs(totalStats.p50), 10, true)} ${pad(formatMs(inferStats.p50), 10, true)} ${pad(formatSpeedFactor(speedStats.avg), 11, true)}`,
    );
  }
  console.log("");

  console.log("Recent");
  for (const sample of samples.slice(-last).reverse()) {
    const stamp = sample.timestamp.replace("T", " ").replace(/\.\d+Z$/, "Z");
    if (sample.outcome !== "ok" || !sample.metrics) {
      console.log(`  ${stamp}  ${sample.clientId}  ${sample.route}  error=${sample.error ?? "unknown"}`);
      continue;
    }

    console.log(
      `  ${stamp}  ${sample.clientId}  ${sample.route}  total=${formatMs(sample.metrics.totalMs)} infer=${formatMs(sample.metrics.inferenceMs)} audio=${formatMs(sample.metrics.audioDurationMs)} speed=${formatSpeedFactor(getSpeedFactor(sample.metrics))} model=${sample.modelId}`,
    );
  }
}

function printTranscriptionMetrics(metrics: TranscriptionMetrics): void {
  console.error(`trace: ${metrics.traceId}`);
  console.error(`audio: ${formatMs(metrics.audioDurationMs)} (${formatBytes(metrics.inputBytes)})`);
  console.error(
    `stages: file_check=${formatMs(metrics.fileCheckMs)} model_check=${formatMs(metrics.modelCheckMs)} model_load=${formatMs(metrics.modelLoadMs)} audio_load=${formatMs(metrics.audioLoadMs)} audio_prepare=${formatMs(metrics.audioPrepareMs)} inference=${formatMs(metrics.inferenceMs)}`,
  );
  console.error(`total: ${formatMs(metrics.totalMs)} (${formatSpeed(metrics.realtimeFactor)})`);
}

export function formatWordTimings(words: WordTiming[]): string[] {
  if (words.length === 0) {
    return ["timestamps: unavailable"];
  }

  const startWidth = Math.max("start".length, ...words.map((word) => formatSeconds(word.start).length));
  const endWidth = Math.max("end".length, ...words.map((word) => formatSeconds(word.end).length));
  const confidenceWidth = Math.max("conf".length, ...words.map((word) => formatConfidence(word.confidence).length));
  const rows = [
    `timestamps (${words.length} words):`,
    `  ${pad("start", startWidth, true)}  ${pad("end", endWidth, true)}  ${pad("conf", confidenceWidth, true)}  word`,
  ];

  for (const word of words) {
    rows.push(
      `  ${pad(formatSeconds(word.start), startWidth, true)}  ${pad(formatSeconds(word.end), endWidth, true)}  ${pad(formatConfidence(word.confidence), confidenceWidth, true)}  ${word.word}`,
    );
  }

  return rows;
}

function printWordTimings(words: WordTiming[]): void {
  for (const line of formatWordTimings(words)) {
    console.error(line);
  }
}

function printBenchmarkSummary(results: FileTranscriptionResult[]): void {
  const metrics = results.map((result) => result.metrics).filter((value): value is TranscriptionMetrics => Boolean(value));
  if (metrics.length === 0) {
    return;
  }

  const totalStats = computeStats(metrics.map((value) => value.totalMs));
  const inferenceStats = computeStats(metrics.map((value) => value.inferenceMs));
  const speedStats = computeStats(
    metrics
      .map((value) => (value.realtimeFactor > 0 ? 1 / value.realtimeFactor : 0))
      .filter((value) => value > 0),
  );
  const audioDuration = metrics[0].audioDurationMs;

  console.log("");
  console.log(`audio duration: ${formatMs(audioDuration)}`);
  console.log(`total: ${formatStat(totalStats, formatMs)}`);
  console.log(`inference: ${formatStat(inferenceStats, formatMs)}`);
  console.log(`speed: ${formatStat(speedStats, formatSpeedFactor)}`);
}

function computeStats(values: number[]): { avg: number; p50: number; p95: number; min: number; max: number } {
  const sorted = [...values].sort((left, right) => left - right);
  const sum = sorted.reduce((accumulator, value) => accumulator + value, 0);
  return {
    avg: sum / sorted.length,
    p50: sorted[Math.floor(sorted.length * 0.5)],
    p95: sorted[Math.floor(sorted.length * 0.95)],
    min: sorted[0],
    max: sorted[sorted.length - 1],
  };
}

function formatStat(
  stats: { avg: number; p50: number; p95: number; min: number; max: number },
  formatter: (value: number) => string,
): string {
  return `avg=${formatter(stats.avg)} p50=${formatter(stats.p50)} p95=${formatter(stats.p95)} min=${formatter(stats.min)} max=${formatter(stats.max)}`;
}

function formatMs(value: number): string {
  if (value >= 1000) {
    return `${(value / 1000).toFixed(2)}s`;
  }
  return `${Math.round(value)}ms`;
}

function formatSeconds(value: number): string {
  return `${value.toFixed(2)}s`;
}

function formatConfidence(value: number): string {
  return value > 0 ? value.toFixed(2) : "-";
}

function pad(value: string, width: number, left = false): string {
  const padding = Math.max(width - value.length, 0);
  return left ? `${" ".repeat(padding)}${value}` : `${value}${" ".repeat(padding)}`;
}

function readPerformanceSamples(logPath: string): PerformanceSample[] {
  return readFileSync(logPath, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line) as PerformanceSample);
}

function resolveLogPath(target: string): string {
  const home = getVoxHome();
  switch (target) {
    case "daemon":
      return join(home, "logs", "voxd.log");
    case "performance":
      return join(home, "performance.jsonl");
    case "voice":
      return join(home, "voice.jsonl");
    default:
      throw new Error(`Unknown logs target: ${target}`);
  }
}

function readOption(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return args[index + 1];
}

function getSpeedFactor(metrics: TranscriptionMetrics): number {
  if (metrics.realtimeFactor && Number.isFinite(metrics.realtimeFactor) && metrics.realtimeFactor > 0) {
    return 1 / metrics.realtimeFactor;
  }
  if (metrics.audioDurationMs > 0 && metrics.inferenceMs > 0) {
    return metrics.audioDurationMs / metrics.inferenceMs;
  }
  return 0;
}

function formatBytes(value: number): string {
  if (value >= 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(1)}MB`;
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(0)}KB`;
  }
  return `${value}B`;
}

function formatSpeed(rtf: number): string {
  if (rtf <= 0) {
    return "n/a";
  }
  return `${(1 / rtf).toFixed(2)}x realtime`;
}

function formatSpeedFactor(value: number): string {
  return `${value.toFixed(2)}x realtime`;
}

function readRuntimeInfo(): RuntimeInfo | null {
  const discovery = new RuntimeDiscovery();
  return discovery.read();
}

function processIsRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function findListeningPid(port: number): number | null {
  const result = Bun.spawnSync([
    "lsof",
    "-nP",
    `-iTCP:${port}`,
    "-sTCP:LISTEN",
    "-t",
  ], {
    stdout: "pipe",
    stderr: "ignore",
  });

  if (result.exitCode !== 0) {
    return null;
  }

  const output = result.stdout.toString().trim().split("\n").find(Boolean);
  const pid = Number(output);
  return Number.isInteger(pid) && pid > 0 ? pid : null;
}

async function waitForEnter(): Promise<void> {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  await new Promise<void>((resolvePromise) => {
    rl.question("", () => {
      rl.close();
      resolvePromise();
    });
  });
}

function launchTui(): void {
  const tuiPath = join(REPO_ROOT, "packages", "tui", "index.tsx");
  const proc = Bun.spawnSync(["bun", "run", tuiPath], {
    cwd: REPO_ROOT,
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
  });
  process.exit(proc.exitCode ?? 0);
}

function printUsage(): void {
  console.log(`Vox CLI

Usage:
  vox daemon start|stop|status
  vox doctor
  vox models list|install|preload [modelId]
  vox warmup status|start [modelId]
  vox warmup schedule [delayMs] [modelId]
  vox perf dashboard [--client <clientId>] [--route <route>] [--last <n>]
  vox logs [daemon|performance|voice] [--tail <n>]
  vox transcribe file [--metrics] [--timestamps] <path>
  vox transcribe bench <path> [runs]
  vox transcribe status
  vox transcribe cancel [sessionId]
  vox transcribe live [--timestamps]
  vox tui`);
}

if (import.meta.main) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
