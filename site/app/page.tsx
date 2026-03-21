import Link from "next/link";
import { ArrowUpRight, Activity, AudioLines, Boxes, Download, Github, Radar, TerminalSquare, Waypoints } from "lucide-react";
import { CopyCommand } from "../components/copy-command";
import { ScreenshotLightbox } from "../components/screenshot-lightbox";

const featureCards = [
  {
    icon: AudioLines,
    title: "Fast local inference",
    body: "Swift services host Parakeet locally so apps can preload the model ahead of speech instead of paying a cold-start tax on the first command.",
  },
  {
    icon: Radar,
    title: "Instrumentation first",
    body: "Every transcription carries stage timings and dimensions for clientId, route, and modelId so operators can inspect real latency instead of guessing.",
  },
  {
    icon: Boxes,
    title: "Multi-client runtime",
    body: "One daemon serves menu bar apps, browser extensions, editor integrations, and the CLI without each reinventing the runtime.",
  },
  {
    icon: Waypoints,
    title: "One protocol surface",
    body: "Bun CLI for operator workflows, TypeScript SDK for embedded app integrations, both over local WebSocket JSON-RPC.",
  },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <header className="sticky top-0 z-50 border-b border-line bg-canvas/92 backdrop-blur-xl px-6 sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-6xl items-center justify-between py-3">
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
            <Link href="/blog" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Blog
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

      {/* Hero */}
      <section className="relative overflow-hidden px-6 pb-20 pt-16 sm:px-8 lg:px-12">
        <div className="hero-mesh pointer-events-none absolute inset-0" />
        <div className="hero-grid pointer-events-none absolute inset-x-0 top-0 h-[40rem]" />
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-12 py-12 lg:grid-cols-[1.3fr_0.7fr] lg:items-end lg:gap-14">
            <div>
              <h1 className="max-w-[18ch] overflow-visible font-display text-4xl leading-[1.08] tracking-[-0.04em] sm:text-6xl lg:text-[5.8rem]">
                One engine to power <em className="text-emerald">all</em> your voice apps.
              </h1>
              <p className="mt-8 max-w-lg text-base leading-8 text-secondary">
                Talk anywhere, instantly. On-device transcription that runs as a lightweight macOS daemon — one runtime for every app on your machine.
              </p>

              <div className="mt-10 flex flex-col items-start gap-4 sm:flex-row sm:items-center">
                <Link
                  href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                  className="group inline-flex h-11 items-center gap-2 rounded-lg bg-emerald-500 px-6 font-mono text-[12px] uppercase tracking-[0.1em] text-black transition-all hover:bg-emerald-400"
                >
                  <Download className="h-3.5 w-3.5" />
                  Download for macOS
                </Link>
                <Link
                  href="/docs/overview"
                  className="group inline-flex h-11 items-center gap-2 rounded-[3px_8px_8px_3px] border border-line-strong px-5 font-mono text-[12px] uppercase tracking-[0.1em] text-secondary transition-all hover:border-accent/50 hover:text-ink hover:bg-wave"
                >
                  Get started with the docs
                  <ArrowUpRight className="h-3.5 w-3.5 opacity-40 transition-all group-hover:opacity-70 group-hover:-translate-y-px group-hover:translate-x-px" />
                </Link>
              </div>
            </div>

            <div className="signal-panel rounded-xl border border-line-strong bg-panel p-5 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Operator view</span>
                <TerminalSquare className="h-4 w-4 text-accent" />
              </div>
              <div className="mt-4 rounded-lg border border-line bg-canvas p-4 font-mono text-[12px] leading-6 text-secondary">
                <div className="text-muted">$ vox perf --client cli</div>
                <div className="mt-2 text-ink">p50=132ms p95=197ms 35x realtime</div>
                <div className="mt-3 text-muted">$ vox transcribe /tmp/sample.wav</div>
                <div className="text-ink">done: 127ms (35x realtime)</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Runtime pillars */}
      <section id="runtime" className="border-y border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="mb-14">
            <h2 className="max-w-[20ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl">
              Built for products with more than one caller.
            </h2>
          </div>
          <div className="grid gap-6 sm:gap-8">
            {featureCards.map(({ icon: Icon, title, body }) => (
              <article key={title} className="grid items-baseline gap-x-5 gap-y-1 sm:grid-cols-[2.5rem_12rem_1fr]">
                <Icon className="hidden h-4 w-4 text-accent sm:block" strokeWidth={1.7} />
                <h3 className="font-display text-xl italic tracking-tight sm:text-2xl">{title}</h3>
                <p className="text-[15px] leading-7 text-secondary sm:col-start-3">{body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Observability */}
      <section id="perf" className="px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-12 lg:grid-cols-2 lg:items-start">
            <div>
              <h2 className="max-w-[20ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl">
                Measure what operators actually care about.
              </h2>
              <p className="mt-5 max-w-md text-[15px] leading-7 text-secondary">
                Stage timings for every transcription. Slice by client, route, and model.
              </p>
              <div className="mt-8">
                <CopyCommand command="vox tui" />
              </div>
            </div>

            <div className="relative overflow-hidden rounded-xl border border-line-strong bg-panel shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="absolute inset-x-0 top-0 h-24 bg-[radial-gradient(circle_at_top,rgba(52,211,153,0.18),transparent_60%)]" />
              <ScreenshotLightbox
                src="/tui-dashboard.png"
                alt="Vox runtime dashboard showing performance stats, per-client breakdown, and recent transcriptions"
                title="vox tui"
                caption="Runtime dashboard — performance stats, per-client breakdown, and recent transcriptions at a glance."
                className="relative"
              />
            </div>
          </div>
        </div>
      </section>

      {/* Get started */}
      <section className="border-t border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="mb-14">
            <h2 className="max-w-[20ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl">
              Install once, transcribe anywhere.
            </h2>
            <p className="mt-5 max-w-lg text-[15px] leading-7 text-secondary">
              Vox runs as a lightweight daemon on your Mac. Install the companion app or use the CLI — either way, any web app on your machine gets local transcription for free.
            </p>
          </div>

          <div className="grid gap-8 lg:grid-cols-2">
            <div className="rounded-xl border border-line-strong bg-canvas p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="mb-4 flex items-center gap-3">
                <Download className="h-4 w-4 text-accent" />
                <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">Download</span>
              </div>
              <p className="text-[15px] leading-7 text-secondary">
                Drag Vox to Applications. The daemon starts automatically on login — nothing to manage, nothing to close.
              </p>
              <div className="mt-5">
                <Link
                  href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                  className="inline-flex h-10 items-center gap-2 rounded-lg bg-emerald-500 px-5 font-mono text-[11px] uppercase tracking-[0.1em] text-black transition-all hover:bg-emerald-400"
                >
                  <Download className="h-3.5 w-3.5" />
                  Vox.dmg
                </Link>
              </div>
            </div>

            <div className="rounded-xl border border-line-strong bg-canvas p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="mb-4 flex items-center gap-3">
                <TerminalSquare className="h-4 w-4 text-accent" />
                <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">CLI</span>
              </div>
              <div className="font-mono text-[12px] leading-7">
                <div className="text-muted">$ npx @vox/cli install</div>
                <div className="text-secondary">daemon installed, LaunchAgent registered</div>
                <div className="mt-3 text-muted">$ npx @vox/cli doctor</div>
                <div className="text-ink">daemon: running</div>
                <div className="text-ink">backend: parakeet</div>
                <div className="text-accent">ready</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <footer className="px-6 pb-28 pt-14 sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-6xl flex-col gap-6 border-t border-line pt-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <div className="font-mono text-[10px] uppercase tracking-[0.18em] text-muted">Vox</div>
            <p className="mt-2 max-w-sm text-sm leading-7 text-secondary">
              Open-source on-device transcription for macOS.
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
