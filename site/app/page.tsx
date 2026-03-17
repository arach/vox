import Link from "next/link";
import { ArrowUpRight, Activity, AudioLines, Boxes, Github, Radar, TerminalSquare, Waypoints } from "lucide-react";
import { CopyCommand, CopyCommandBlock } from "../components/copy-command";

const featureCards = [
  {
    icon: AudioLines,
    title: "Warm, local inference",
    body: "Swift services host Parakeet locally so apps can warm the model ahead of speech instead of paying a cold-start tax on the first command.",
  },
  {
    icon: Radar,
    title: "Instrumentation first",
    body: "Every transcription carries stage timings and dimensions for clientId, route, and modelId so operators can inspect real latency instead of guessing.",
  },
  {
    icon: Boxes,
    title: "Multi-client runtime",
    body: "One daemon can serve a menu bar app, Raycast command, browser extension, editor integration, and the CLI without each client reinventing the runtime.",
  },
  {
    icon: Waypoints,
    title: "One protocol surface",
    body: "Use the Bun CLI for operator workflows or the TypeScript SDK for embedded app integrations over local WebSocket JSON-RPC.",
  },
];

const operatorSteps = [
  ["git clone https://github.com/arach/vox.git && cd vox", "Pull the runtime, CLI, SDK, docs, and site in one repository."],
  ["bun install", "Install the Bun workspace and site dependencies."],
  ["bun run build", "Build the SDK, CLI, and Swift daemon."],
  ["bun packages/cli/src/index.ts doctor", "Verify that the daemon, backend, and model state are healthy on this Mac."],
];

export default function Home() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <header className="sticky top-0 z-50 border-b border-line bg-canvas/92 backdrop-blur-xl">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-3 sm:px-8 lg:px-12">
          <div className="flex items-center gap-3 font-mono text-[12px] uppercase tracking-[0.14em]">
            <Link href="/" className="text-ink">
              Vox
            </Link>
            <span className="text-muted">/</span>
            <span className="text-muted">Local runtime</span>
          </div>

          <div className="flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.12em] text-muted">
            <Link href="/docs/overview" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Docs
            </Link>
            <Link href="#runtime" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Runtime
            </Link>
            <Link href="#perf" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Perf
            </Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              GitHub
            </Link>
          </div>
        </div>
      </header>

      <section className="relative overflow-hidden px-6 pb-20 pt-16 sm:px-8 lg:px-12">
        <div className="hero-mesh pointer-events-none absolute inset-0" />
        <div className="hero-grid pointer-events-none absolute inset-x-0 top-0 h-[40rem]" />
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-14 py-12 lg:grid-cols-[1.1fr_0.9fr] lg:items-start">
            <div className="max-w-4xl">
              <p className="mb-4 font-mono text-[11px] uppercase tracking-[0.16em] text-accent">
                Developer-first transcription infrastructure
              </p>
              <h1 className="max-w-4xl font-display text-4xl leading-[1.02] tracking-[-0.04em] sm:text-6xl lg:text-[5.4rem]">
                Local transcription that gets warm before speech and keeps latency visible after it lands.
              </h1>
              <p className="mt-8 max-w-2xl text-base leading-8 text-secondary sm:text-lg">
                Vox gives you a real runtime surface instead of a black-box SDK: a Swift daemon, a Bun CLI, a TypeScript client, explicit warm-up semantics, and telemetry tagged by client, route, and model.
              </p>

              <div className="mt-10 flex flex-col items-start gap-4 sm:flex-row sm:items-center">
                <CopyCommand command="git clone https://github.com/arach/vox.git && cd vox && bun install" />
                <Link
                  href="/docs/overview"
                  className="group inline-flex h-11 items-center gap-2 rounded-md border border-line-strong bg-panel px-5 text-sm font-medium text-ink transition-colors hover:border-accent/50 hover:bg-wave"
                >
                  Open the docs
                  <ArrowUpRight className="h-3.5 w-3.5 opacity-60 transition-transform group-hover:-translate-y-px group-hover:translate-x-px" />
                </Link>
              </div>

              <div className="mt-10 grid max-w-2xl gap-3 sm:grid-cols-3">
                {[
                  ["hot path", "~151ms average inference"],
                  ["telemetry", "clientId / route / modelId"],
                  ["deployment", "CLI, SDK, daemon"],
                ].map(([label, value]) => (
                  <div key={label} className="rounded-xl border border-line bg-panel px-4 py-4">
                    <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">{label}</div>
                    <div className="mt-2 text-sm leading-6 text-secondary">{value}</div>
                  </div>
                ))}
              </div>
            </div>

            <div className="signal-panel rounded-2xl border border-line-strong bg-panel p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Operator view</span>
                <TerminalSquare className="h-4 w-4 text-accent" />
              </div>
              <div className="mt-6 rounded-xl border border-line bg-canvas p-5 font-mono text-[12px] leading-6 text-secondary">
                <div className="text-muted">$ vox doctor</div>
                <div className="mt-2 text-ink">ready: true</div>
                <div>backend: parakeet</div>
                <div>model: warm</div>
                <div className="mt-4 text-muted">$ vox perf dashboard --client raycast</div>
                <div className="mt-2 text-ink">total: avg=151ms p50=132ms p95=197ms</div>
                <div>inference: avg=151ms p50=131ms p95=197ms</div>
                <div>speed: avg=35.25x realtime</div>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {["clientId", "route", "modelId", "warmup", "json-rpc"].map((item) => (
                  <span
                    key={item}
                    className="rounded-md border border-line bg-wave px-3 py-1 font-mono text-[10px] uppercase tracking-[0.14em] text-muted"
                  >
                    {item}
                  </span>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="runtime" className="border-y border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-10 lg:grid-cols-[0.8fr_1.2fr]">
            <div>
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-accent">Runtime shape</p>
              <h2 className="mt-4 font-display text-3xl leading-tight tracking-[-0.03em] sm:text-5xl">
                Built for products with more than one caller.
              </h2>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              {featureCards.map(({ icon: Icon, title, body }) => (
                <article key={title} className="rounded-xl border border-line bg-canvas px-5 py-6 transition-transform duration-300 hover:-translate-y-1">
                  <Icon className="h-5 w-5 text-accent" strokeWidth={1.7} />
                  <h3 className="mt-4 text-lg font-semibold tracking-tight">{title}</h3>
                  <p className="mt-3 text-sm leading-7 text-secondary">{body}</p>
                </article>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section id="perf" className="px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[0.95fr_1.05fr]">
          <div>
            <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-accent">Observability</p>
            <h2 className="mt-4 font-display text-3xl leading-tight tracking-[-0.03em] sm:text-5xl">
              Measure the audio-to-text path the way operators actually think.
            </h2>
            <p className="mt-6 max-w-xl text-base leading-8 text-secondary">
              Vox records stage timings for file checks, model checks, warm loads, audio prep, and inference. Then it writes tagged performance samples you can slice by client, route, and model.
            </p>
            <div className="mt-10 grid gap-3">
              <CopyCommandBlock command="vox transcribe file --metrics /tmp/sample.wav" label="Inspect one run with per-stage timings." />
              <CopyCommandBlock command="vox transcribe bench /tmp/sample.wav 5" label="Measure warm-path throughput over repeated runs." />
              <CopyCommandBlock command="vox perf dashboard --client browser-extension" label="See latency distributions for a specific integration surface." />
            </div>
          </div>

          <div className="relative overflow-hidden rounded-2xl border border-line-strong bg-panel p-6 text-ink shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
            <div className="absolute inset-x-0 top-0 h-32 bg-[radial-gradient(circle_at_top,rgba(52,211,153,0.18),transparent_60%)]" />
            <div className="relative">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">performance.jsonl</span>
                <Activity className="h-4 w-4 text-accent-bright" />
              </div>
              <div className="mt-6 space-y-3 rounded-xl border border-line bg-canvas p-5 font-mono text-[12px] leading-6 text-secondary">
                <div>{`{"clientId":"vox-cli","route":"transcribe.file","modelId":"parakeet:v3","totalMs":127}`}</div>
                <div>{`{"clientId":"raycast","route":"transcribe.file","modelId":"parakeet:v3","inferenceMs":268}`}</div>
                <div>{`{"clientId":"browser-extension","route":"transcribe.file","modelId":"parakeet:v3","audioDurationMs":5110}`}</div>
              </div>
              <div className="mt-6 border-t border-line pt-5 text-sm leading-7 text-secondary">
                The same tags can back a local dashboard today and a metrics backend later. Start local, export when you need to.
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="border-t border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-12 lg:grid-cols-[0.85fr_1.15fr]">
            <div>
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-accent">Get started</p>
              <h2 className="mt-4 font-display text-3xl leading-tight tracking-[-0.03em] sm:text-5xl">
                A clean path from clone to a measurable runtime.
              </h2>
              <p className="mt-6 max-w-md text-base leading-8 text-secondary">
                The site stays simple on purpose. The useful loop is operational: verify the daemon, warm the model, run a real transcription, then inspect per-client latency.
              </p>
            </div>
            <div className="space-y-3">
              {operatorSteps.map(([command, label]) => (
                <CopyCommandBlock key={command} command={command} label={label} />
              ))}
            </div>
          </div>
        </div>
      </section>

      <footer className="px-6 pb-28 pt-16 sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-6xl flex-col gap-8 border-t border-line pt-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <div className="font-mono text-[10px] uppercase tracking-[0.18em] text-muted">Vox</div>
            <p className="mt-3 max-w-md text-sm leading-7 text-secondary">
              Open-source local transcription infrastructure for macOS. Swift services, Bun tooling, warm-up semantics, and performance visibility by design.
            </p>
          </div>
          <div className="flex gap-5 font-mono text-[10px] uppercase tracking-[0.16em] text-muted">
            <Link href="/docs/overview" className="transition-colors hover:text-ink">
              Docs
            </Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-2 transition-colors hover:text-ink">
              <Github className="h-3.5 w-3.5" />
              GitHub
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}
