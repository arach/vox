import Link from "next/link";
import { ArrowUpRight, AudioLines, Boxes, Download, Github, Radar, TerminalSquare, Waypoints } from "lucide-react";
import { CopyCommand } from "../components/copy-command";
import { ScreenshotLightbox } from "../components/screenshot-lightbox";

const featureCards = [
  {
    icon: AudioLines,
    idx: "01",
    title: "APPLE APPS",
    body: "Swift owns the embed surface. If an Apple app can keep speech local and in process, Vox lets it do that.",
  },
  {
    icon: Radar,
    idx: "02",
    title: "WARM-UP IS PART OF THE PRODUCT",
    body: "Cold and warm state stay visible. Apps and tools can schedule, inspect, and reason about model readiness instead of guessing where the delay comes from.",
  },
  {
    icon: Boxes,
    idx: "03",
    title: "COMPANION, NOT CLOUD",
    body: "Vox Companion serves browser integrations, local tools, and the CLI on the same machine. You do not need to turn every voice workflow into a cloud service.",
  },
  {
    icon: Waypoints,
    idx: "04",
    title: "SHARED SURFACES",
    body: "Swift packages, `voxd`, `@voxd/sdk`, `@voxd/client`, and `@voxd/cli` all share the same runtime ideas, telemetry, and lifecycle semantics.",
  },
];

const surfaceCards = [
  {
    eyebrow: "Swift packages",
    title: "VoxCore · VoxEngine · VoxService · VoxBridge",
    body: "The embed surface for Apple apps that want speech in process, with explicit warm-up and easy-to-follow runtime behavior.",
    href: "/docs/overview",
    cta: "Open the overview",
  },
  {
    eyebrow: "Companion runtime",
    title: "voxd",
    body: "The local daemon that stays warm for shared-process clients and gives tools a steady WebSocket JSON-RPC runtime to talk to.",
    href: "/docs/runtime",
    cta: "Read runtime docs",
  },
  {
    eyebrow: "Bun and Node SDK",
    title: "@voxd/sdk",
    body: "Typed companion client for local tools, agents, and app-side flows that want direct access to the daemon surface.",
    href: "/docs/sdk",
    cta: "See the SDK",
  },
  {
    eyebrow: "Browser SDK",
    title: "@voxd/client",
    body: "HTTP bridge client for browser apps that need local speech while keeping the runtime on the same machine.",
    href: "/web",
    cta: "Explore the web SDK",
  },
  {
    eyebrow: "Operator CLI",
    title: "@voxd/cli",
    body: "Doctor, voices, benchmarks, warm-up controls, and dashboards for day-to-day work with the stack.",
    href: "/docs/quickstart",
    cta: "Quickstart",
  },
];

const relatedProjects = [
  {
    name: "Talklie",
    href: "https://usetalklie.com",
    body: "A related product built around the same local voice ideas.",
  },
  {
    name: "Linea",
    href: "https://uselinea.com",
    body: "Another native client direction built around the same local-first approach.",
  },
  {
    name: "Lattices",
    href: "https://lattices.dev",
    body: "Related infrastructure work for local agent workflows.",
  },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      {/* Nav — minimal, pushed to edges */}
      <header className="sticky top-0 z-50 border-b border-line bg-canvas/95 backdrop-blur-md px-6 sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-7xl items-center justify-between py-3">
          <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.16em]">
            <Link href="/" className="flex items-center gap-2.5 text-ink">
              <img src="/logo.svg" alt="Vox" className="h-5 w-5" />
              <span className="font-medium">Vox</span>
            </Link>
          </div>

          <nav className="flex items-center gap-1 font-mono text-[10px] uppercase tracking-[0.14em] text-muted">
            <Link href="/docs/overview" className="px-3 py-1.5 transition-colors hover:text-ink">
              Docs
            </Link>
            <Link href="/blog" className="px-3 py-1.5 transition-colors hover:text-ink">
              Blog
            </Link>
            <Link href="#surfaces" className="px-3 py-1.5 transition-colors hover:text-ink">
              Packages
            </Link>
            <Link href="#companion" className="px-3 py-1.5 transition-colors hover:text-ink">
              Companion
            </Link>
            <Link href="#perf" className="px-3 py-1.5 transition-colors hover:text-ink">
              Perf
            </Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="px-3 py-1.5 transition-colors hover:text-ink">
              GitHub
            </Link>
          </nav>
        </div>
      </header>

      {/* Hero — big brand moment */}
      <section className="relative overflow-hidden px-6 pb-20 pt-16 sm:px-8 sm:pb-32 sm:pt-24 lg:px-12">
        <div className="hero-mesh pointer-events-none absolute inset-0" />
        <div className="hero-grid pointer-events-none absolute inset-x-0 top-0 h-[40rem]" />
        <div className="mx-auto max-w-7xl">

          {/* Brand block: logo + wordmark */}
          <div className="relative mb-16 sm:mb-20">
            <div className="flex flex-col items-center gap-4">
              <img
                src="/logo.svg"
                alt="Vox"
                className="h-[120px] w-[120px] sm:h-[140px] sm:w-[140px] lg:h-[160px] lg:w-[160px]"
              />
              <div className="vox-wordmark text-ink">
                VOX
              </div>
            </div>
          </div>

          {/* Two-column: copy + terminal */}
          <div className="grid gap-16 lg:grid-cols-[1.4fr_0.6fr] lg:items-end lg:gap-20">
            <div>
              <h1 className="max-w-[18ch] font-sans text-[clamp(2rem,5vw,3.5rem)] font-light leading-[1.1] tracking-[-0.03em]">
                Local voice runtime for Apple apps, companion clients, and tools.
              </h1>

              <p className="mt-8 max-w-md text-[15px] leading-8 text-secondary">
                Vox provides Swift packages for direct Apple embed mode, `voxd` for the local companion runtime, `@voxd/sdk` for local tools, `@voxd/client` for browser apps, and a CLI for checks and benchmarks.
              </p>

              <div className="mt-12 flex flex-col items-start gap-3 sm:flex-row sm:items-center">
                <Link
                  href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                  className="group inline-flex h-11 items-center gap-2.5 rounded-none border border-line-strong px-6 font-mono text-[11px] uppercase tracking-[0.12em] text-ink transition-all hover:border-ink hover:bg-ink hover:text-canvas"
                >
                  <Download className="h-3.5 w-3.5" />
                  Download for macOS
                </Link>
                <Link
                  href="/docs/overview"
                  className="group inline-flex h-11 items-center gap-2 rounded-none border border-line-strong px-6 font-mono text-[11px] uppercase tracking-[0.12em] text-muted transition-colors hover:border-ink/40 hover:text-ink"
                >
                  Read the docs
                  <ArrowUpRight className="h-3 w-3 opacity-30 transition-opacity group-hover:opacity-60" />
                </Link>
              </div>

              <div className="mt-8">
                <CopyCommand command="bun add -g @voxd/cli@latest" />
                <p className="mt-2 font-mono text-[10px] tracking-wide text-muted">
                  a quick way to get a local runtime, doctor, warm-up, and benchmarks
                </p>
              </div>
            </div>

            {/* Operator panel */}
            <div className="signal-panel rounded-none border border-line-strong bg-panel p-5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Operator view</span>
                <TerminalSquare className="h-3.5 w-3.5 text-muted" />
              </div>
              <div className="mt-4 border border-line bg-canvas p-4 font-mono text-[12px] leading-6 text-secondary">
                <div className="text-muted">$ vox perf --client cli</div>
                <div className="mt-2 text-ink">p50=132ms p95=197ms 35x realtime</div>
                <div className="mt-3 text-muted">$ vox transcribe /tmp/sample.wav</div>
                <div className="text-ink">done: 127ms (35x realtime)</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Divider strip */}
      <div className="mx-auto max-w-7xl px-6 sm:px-8 lg:px-12">
        <div className="flex items-center gap-4 font-mono text-[9px] uppercase tracking-[0.2em] text-muted">
          <div className="h-px flex-1 bg-line" />
          <span>PACKAGES AND RUNTIME</span>
          <div className="h-px flex-1 bg-line" />
        </div>
      </div>

      <section id="surfaces" className="px-6 py-20 sm:px-8 sm:py-24 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="mb-14 sm:mb-16">
            <p className="mb-4 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">PACKAGES</p>
            <h2 className="max-w-[18ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl lg:text-6xl">
              Pick the surface that fits your app.
            </h2>
            <p className="mt-6 max-w-2xl text-[15px] leading-7 text-secondary">
              The same runtime ideas show up in different forms depending on where the voice work lives: in-process Swift, the local companion, the browser bridge, or operator tooling.
            </p>
          </div>

          <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
            {surfaceCards.map((card) => (
              <article key={card.title} className="rounded-none border border-line bg-panel p-6">
                <p className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">{card.eyebrow}</p>
                <h3 className="mt-4 text-lg font-semibold tracking-tight text-ink">{card.title}</h3>
                <p className="mt-3 text-[14px] leading-7 text-secondary">{card.body}</p>
                <Link
                  href={card.href}
                  className="group mt-5 inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.14em] text-muted transition-colors hover:text-ink"
                >
                  {card.cta}
                  <ArrowUpRight className="h-3 w-3 opacity-40 transition-all group-hover:opacity-70 group-hover:-translate-y-px group-hover:translate-x-px" />
                </Link>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Runtime pillars — ruled list */}
      <section id="companion" className="px-6 py-20 sm:px-8 sm:py-28 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="mb-16 sm:mb-20">
            <p className="mb-4 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">COMPANION</p>
            <h2 className="max-w-[22ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl lg:text-6xl">
              Embed in apps. Run companion mode for the web and local tools.
            </h2>
          </div>
          <div className="grid gap-px border-t border-line">
            {featureCards.map(({ icon: Icon, idx, title, body }) => (
              <article key={title} className="feature-row grid items-baseline gap-x-6 gap-y-2 border-b border-line py-7 grid-cols-[2.5rem_1fr] sm:grid-cols-[3rem_12rem_1fr] sm:py-8">
                <span className="feature-index">{idx}</span>
                <h3 className="font-mono text-[12px] font-medium tracking-[0.08em] text-ink">{title}</h3>
                <p className="col-start-2 text-[14px] leading-7 text-secondary sm:col-start-3">{body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="border-t border-line px-6 py-20 sm:px-8 sm:py-24 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="mb-12">
            <p className="mb-4 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">RELATED PROJECTS</p>
            <h2 className="max-w-[18ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-4xl lg:text-5xl">
              A few related projects.
            </h2>
          </div>
          <div className="grid gap-4 lg:grid-cols-3">
            {relatedProjects.map((project) => (
              <Link
                key={project.name}
                href={project.href}
                target="_blank"
                rel="noreferrer noopener"
                className="group rounded-none border border-line bg-panel p-6 transition-colors hover:border-line-strong hover:bg-wave"
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">{project.name}</span>
                  <ArrowUpRight className="h-3.5 w-3.5 text-muted transition-all group-hover:text-ink group-hover:-translate-y-px group-hover:translate-x-px" />
                </div>
                <p className="mt-4 text-[14px] leading-7 text-secondary">{project.body}</p>
                <p className="mt-4 font-mono text-[10px] tracking-[0.14em] text-muted">{project.href.replace("https://", "")}</p>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* Observability */}
      <section id="perf" className="border-t border-line bg-panel px-6 py-20 sm:px-8 sm:py-28 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="grid gap-14 lg:grid-cols-2 lg:items-start">
            <div>
              <p className="mb-4 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">OBSERVABILITY</p>
              <h2 className="max-w-[22ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl lg:text-6xl">
                See where the time goes.
              </h2>
              <p className="mt-6 max-w-md text-[15px] leading-7 text-secondary">
                Every voice request carries stage timings. Slice by client, route, model, and voice.
              </p>
              <div className="mt-8">
                <CopyCommand command="vox tui" />
              </div>
            </div>

            <div className="relative overflow-hidden border border-line-strong bg-canvas">
              <ScreenshotLightbox
                src="/tui-dashboard.png"
                alt="Vox dashboard showing performance stats, per-client breakdown, and recent voice activity"
                title="vox tui"
                caption="Performance dashboard with a per-client breakdown and recent voice activity."
                className="relative"
              />
            </div>
          </div>
        </div>
      </section>

      {/* Install */}
      <section className="border-t border-line px-6 py-20 sm:px-8 sm:py-28 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="mb-16 sm:mb-20">
            <p className="mb-4 font-mono text-[10px] uppercase tracking-[0.2em] text-muted">GET STARTED</p>
            <h2 className="max-w-[22ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl lg:text-6xl">
              Get the companion running for the web and local tools.
            </h2>
            <p className="mt-6 max-w-lg text-[15px] leading-7 text-secondary">
              Apple apps can embed Vox directly. For browser and shared-process workflows, install the companion app or use the CLI so local web clients and tools can connect to the same warm Vox engine.
            </p>
          </div>

          <div className="grid gap-px lg:grid-cols-2">
            {/* Download card */}
            <div className="border border-line bg-panel p-8">
              <div className="mb-5 flex items-center gap-3">
                <Download className="h-4 w-4 text-muted" />
                <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">Download</span>
              </div>
              <p className="text-[14px] leading-7 text-secondary">
                Drag Vox to Applications. The companion starts automatically on login, so web and tooling integrations have a local bridge ready on the machine.
              </p>
              <div className="mt-6">
                <Link
                  href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                  className="inline-flex h-10 items-center gap-2.5 border border-line-strong px-5 font-mono text-[10px] uppercase tracking-[0.12em] text-ink transition-all hover:border-ink hover:bg-ink hover:text-canvas"
                >
                  <Download className="h-3 w-3" />
                  Vox.dmg
                </Link>
              </div>
            </div>

            {/* CLI card */}
            <div className="border border-line bg-panel p-8">
              <div className="mb-5 flex items-center gap-3">
                <TerminalSquare className="h-4 w-4 text-muted" />
                <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">CLI</span>
              </div>
              <div className="font-mono text-[12px] leading-7">
                <div className="text-muted">$ npx @voxd/cli install</div>
                <div className="text-secondary">Vox Companion installed, LaunchAgent registered</div>
                <div className="mt-3 text-muted">$ npx @voxd/cli doctor</div>
                <div className="text-ink">daemon: running</div>
                <div className="text-ink">backend: parakeet</div>
                <div className="text-ink">ready</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-line px-6 pb-16 pt-16 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-7xl">
          <div className="flex flex-col gap-8 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <div className="flex items-center gap-3">
                <img src="/logo.svg" alt="Vox" className="h-8 w-8" />
                <span className="font-mono text-lg font-medium tracking-[-0.02em] text-ink">VOX</span>
              </div>
              <p className="mt-3 max-w-sm text-[13px] leading-7 text-secondary">
                Open-source local voice stack for Apple platforms.
              </p>
              <p className="mt-1 font-mono text-[10px] tracking-wide text-muted">
                Local-first. Built for Apple apps and companion clients.
              </p>
            </div>
            <div className="flex gap-6 font-mono text-[10px] uppercase tracking-[0.16em] text-muted">
              <Link href="/docs/overview" className="transition-colors hover:text-ink">
                Docs
              </Link>
              <Link href="/blog" className="transition-colors hover:text-ink">
                Blog
              </Link>
              <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-2 transition-colors hover:text-ink">
                <Github className="h-3 w-3" />
                GitHub
              </Link>
            </div>
          </div>
        </div>
      </footer>
    </main>
  );
}
