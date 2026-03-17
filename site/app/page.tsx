import Link from "next/link";
import { ArrowUpRight, Activity, AudioLines, Boxes, Github, Radar, TerminalSquare, Waypoints } from "lucide-react";
import { CopyCommand, CopyCommandBlock } from "../components/copy-command";

const featureCards = [
  {
    icon: AudioLines,
    title: "Warm, local inference",
    body: "Swift services host Parakeet locally so apps can warm the model ahead of speech instead of waiting on first transcription.",
  },
  {
    icon: Radar,
    title: "Instrumentation first",
    body: "Every transcription carries stage timings and dimensions for clientId, route, and modelId so operators can see real latency, not folklore.",
  },
  {
    icon: Boxes,
    title: "Multi-client runtime",
    body: "The daemon is built to serve multiple consumers: menu bar apps, browser extensions, Raycast actions, terminals, and bespoke macOS tooling.",
  },
  {
    icon: Waypoints,
    title: "One protocol surface",
    body: "Use the Bun CLI for operator workflows or the TypeScript SDK for embedded app integrations over local WebSocket JSON-RPC.",
  },
];

const operatorSteps = [
  ["git clone https://github.com/arach/vox.git && cd vox", "Pull the runtime, CLI, SDK, site, and docs in one repository."],
  ["bun install", "Install the Bun workspace and web dependencies."],
  ["bun run build", "Build the SDK, CLI, Swift daemon, and everything needed for local validation."],
  ["bun packages/cli/src/index.ts doctor", "Verify that the daemon, backend, and model state are healthy on this Mac."],
];

export default function Home() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <nav className="fixed bottom-5 left-1/2 z-50 -translate-x-1/2">
        <div className="flex items-center gap-1 rounded-full border border-line-strong bg-canvas/92 px-2 py-2 shadow-[0_10px_40px_rgba(17,24,39,0.12)] backdrop-blur-xl">
          {[
            ["Docs", "/docs/overview"],
            ["GitHub", "https://github.com/arach/vox"],
            ["Runtime", "#runtime"],
            ["Perf", "#perf"],
          ].map(([label, href]) => (
            <Link
              key={label}
              href={href}
              target={href.startsWith("http") ? "_blank" : undefined}
              rel={href.startsWith("http") ? "noreferrer noopener" : undefined}
              className="rounded-full px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.14em] text-muted transition-colors hover:bg-wave hover:text-ink"
            >
              {label}
            </Link>
          ))}
        </div>
      </nav>

      <section className="relative overflow-hidden px-6 pb-20 pt-12 sm:px-8 lg:px-12">
        <div className="hero-mesh pointer-events-none absolute inset-0" />
        <div className="hero-grid pointer-events-none absolute inset-x-0 top-0 h-[32rem]" />
        <div className="mx-auto max-w-6xl">
          <div className="flex items-center justify-between border-b border-line py-4">
            <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-muted">Vox</span>
            <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-muted">macOS transcription runtime</span>
          </div>

          <div className="grid gap-16 py-20 lg:grid-cols-[1.25fr_0.75fr] lg:items-end">
            <div className="max-w-4xl">
              <p className="mb-4 font-mono text-[11px] uppercase tracking-[0.16em] text-accent">
                Voice infrastructure for apps that need to move fast
              </p>
              <h1 className="max-w-4xl font-display text-5xl leading-[0.98] tracking-[-0.045em] sm:text-7xl lg:text-[6.5rem]">
                Transcription that stays <em className="text-muted">local</em>, gets <em className="text-muted">warm</em>, and tells you where the latency went.
              </h1>
              <p className="mt-8 max-w-2xl text-base leading-8 text-secondary sm:text-lg">
                Vox is a standalone macOS runtime with Swift services, a Bun CLI, and a TypeScript SDK for developers who want transcription as infrastructure, not as a black box.
              </p>

              <div className="mt-10 flex flex-col items-start gap-4 sm:flex-row sm:items-center">
                <CopyCommand command="git clone https://github.com/arach/vox.git && cd vox && bun install" />
                <Link
                  href="/docs/overview"
                  className="group inline-flex h-11 items-center gap-2 rounded-full bg-ink px-5 text-sm font-medium text-canvas transition-opacity hover:opacity-92"
                >
                  Read the docs
                  <ArrowUpRight className="h-3.5 w-3.5 opacity-60 transition-transform group-hover:-translate-y-px group-hover:translate-x-px" />
                </Link>
              </div>
            </div>

            <div className="signal-panel rounded-[2rem] border border-line-strong bg-panel p-6 shadow-[0_30px_120px_rgba(17,24,39,0.10)]">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Operator view</span>
                <TerminalSquare className="h-4 w-4 text-accent" />
              </div>
              <div className="mt-6 rounded-[1.5rem] border border-line bg-canvas p-5 font-mono text-[12px] leading-6 text-secondary">
                <div className="text-muted">$ vox perf dashboard --client raycast</div>
                <div className="mt-3 text-ink">total: avg=151ms p50=132ms p95=197ms</div>
                <div>inference: avg=151ms p50=131ms p95=197ms</div>
                <div>speed: avg=35.25x realtime</div>
                <div className="mt-4 text-muted">$ vox warmup schedule 500 parakeet:v3</div>
                <div className="text-ink">state: scheduled</div>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {["clientId", "route", "modelId", "warmup", "perf dashboard"].map((item) => (
                  <span
                    key={item}
                    className="rounded-full border border-line bg-wave px-3 py-1 font-mono text-[10px] uppercase tracking-[0.14em] text-muted"
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
              <h2 className="mt-4 font-display text-4xl leading-tight tracking-[-0.03em] sm:text-5xl">
                Built for app teams, not demo scripts.
              </h2>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              {featureCards.map(({ icon: Icon, title, body }) => (
                <article key={title} className="rounded-[1.5rem] border border-line bg-canvas px-5 py-6 transition-transform duration-300 hover:-translate-y-1">
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
            <h2 className="mt-4 font-display text-4xl leading-tight tracking-[-0.03em] sm:text-5xl">
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

          <div className="relative overflow-hidden rounded-[2rem] border border-line-strong bg-ink p-6 text-canvas shadow-[0_40px_120px_rgba(17,24,39,0.20)]">
            <div className="absolute inset-x-0 top-0 h-32 bg-[radial-gradient(circle_at_top,rgba(39,214,195,0.22),transparent_60%)]" />
            <div className="relative">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-canvas/60">performance.jsonl</span>
                <Activity className="h-4 w-4 text-accent-bright" />
              </div>
              <div className="mt-6 space-y-3 rounded-[1.5rem] border border-white/10 bg-white/5 p-5 font-mono text-[12px] leading-6 text-canvas/84">
                <div>{`{"clientId":"vox-cli","route":"transcribe.file","modelId":"parakeet:v3","totalMs":127}`}</div>
                <div>{`{"clientId":"raycast","route":"transcribe.file","modelId":"parakeet:v3","inferenceMs":268}`}</div>
                <div>{`{"clientId":"browser-extension","route":"transcribe.file","modelId":"parakeet:v3","audioDurationMs":5110}`}</div>
              </div>
              <div className="mt-6 border-t border-white/10 pt-5 text-sm leading-7 text-canvas/70">
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
              <h2 className="mt-4 font-display text-4xl leading-tight tracking-[-0.03em] sm:text-5xl">
                A clean path from clone to healthy runtime.
              </h2>
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
