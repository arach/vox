import Link from "next/link";
import { ArrowUpRight, Download, Github } from "lucide-react";
import { CopyCommand } from "../components/copy-command";
import { ScreenshotLightbox } from "../components/screenshot-lightbox";

const featureRows = [
  { idx: "01", title: "Apple apps", body: "Swift owns the embed surface. If an Apple app can keep speech local and in process, Vox lets it do that." },
  { idx: "02", title: "Warm-up is part of the product", body: "Cold and warm state stay visible. Apps and tools schedule, inspect, and reason about model readiness instead of guessing where the delay comes from." },
  { idx: "03", title: "Companion, not cloud", body: "Vox Companion serves browser integrations, local tools, and the CLI on the same machine. You do not need to turn every voice workflow into a cloud service." },
  { idx: "04", title: "Shared surfaces", body: "Swift packages, voxd, @voxd/sdk, @voxd/client, and @voxd/cli all share the same runtime ideas, telemetry, and lifecycle semantics." },
];

const surfaceCards = [
  { eyebrow: "SWIFT PACKAGES", title: "VoxCore · VoxEngine · VoxService · VoxBridge", body: "The embed surface for Apple apps that want speech in process, with explicit warm-up and easy-to-follow runtime behavior.", href: "/docs/overview", cta: "Open the overview" },
  { eyebrow: "COMPANION RUNTIME", title: "voxd", body: "The local daemon that stays warm for shared-process clients and gives tools a steady WebSocket JSON-RPC runtime to talk to.", href: "/docs/runtime", cta: "Read runtime docs" },
  { eyebrow: "BUN AND NODE SDK", title: "@voxd/sdk", body: "Typed companion client for local tools, agents, and app-side flows that want direct access to the daemon surface.", href: "/docs/sdk", cta: "See the SDK" },
  { eyebrow: "BROWSER SDK", title: "@voxd/client", body: "HTTP bridge client for browser apps that need local speech while keeping the runtime on the same machine.", href: "/web", cta: "Explore the web SDK" },
  { eyebrow: "OPERATOR CLI", title: "@voxd/cli", body: "Doctor, voices, benchmarks, warm-up controls, and dashboards for day-to-day work with the stack.", href: "/docs/quickstart", cta: "Quickstart" },
];

const relatedProjects = [
  { name: "TALKLIE", href: "https://usetalklie.com", body: "A related product built around the same local voice ideas." },
  { name: "LINEA", href: "https://uselinea.com", body: "Another native client direction built around the same local-first approach." },
  { name: "LATTICES", href: "https://lattices.dev", body: "Related infrastructure work for local agent workflows." },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      {/* Sticky status strip */}
      <div className="sticky top-0 z-50 border-b border-line bg-canvas">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-2 font-mono text-[11px] uppercase tracking-[0.14em] text-muted">
          <span className="text-secondary">vox v0.1.0</span>
          <span className="hidden items-center gap-2 text-secondary sm:inline-flex">
            <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-accent" />
            daemon · running
          </span>
          <span>p50 132ms · 35× rt</span>
        </div>
      </div>

      {/* Nav */}
      <header className="border-b border-line">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-3">
            <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm bg-accent" />
            <span className="text-[15px] font-medium tracking-tight text-ink">Vox</span>
          </Link>
          <nav className="flex flex-wrap items-center gap-1 font-mono text-[11px] uppercase tracking-[0.14em] text-muted">
            <Link href="/docs/overview" className="px-2.5 py-1.5 transition-colors hover:text-accent">Docs</Link>
            <Link href="/blog" className="px-2.5 py-1.5 transition-colors hover:text-accent">Blog</Link>
            <Link href="#packages" className="px-2.5 py-1.5 transition-colors hover:text-accent">Packages</Link>
            <Link href="#runtime" className="px-2.5 py-1.5 transition-colors hover:text-accent">Runtime</Link>
            <Link href="#perf" className="px-2.5 py-1.5 transition-colors hover:text-accent">Perf</Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="px-2.5 py-1.5 transition-colors hover:text-accent">GitHub</Link>
          </nav>
        </div>
      </header>

      {/* Hero */}
      <section className="border-b border-line">
        <div className="mx-auto grid max-w-6xl gap-12 px-6 py-20 lg:grid-cols-[1.25fr_1fr] lg:gap-16">
          <div>
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// hero</p>
            <h1 className="mt-5 max-w-[22ch] text-[clamp(1.75rem,3.8vw,2.75rem)] font-medium leading-[1.15] tracking-[-0.03em] text-ink">
              Local voice runtime for Apple apps, companion clients, and tools<span className="text-accent">.</span>
            </h1>
            <p className="mt-6 max-w-md text-[15px] leading-7 text-secondary">
              Vox provides Swift packages for direct Apple embed mode, voxd for the local companion runtime, @voxd/sdk for local tools, @voxd/client for browser apps, and a CLI for checks and benchmarks.
            </p>

            <div className="mt-9 flex flex-wrap items-center gap-3">
              <Link
                href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                className="inline-flex h-10 items-center gap-2 rounded-sm border border-accent bg-accent px-5 font-mono text-[12px] font-medium uppercase tracking-[0.06em] text-canvas"
              >
                <Download className="h-3.5 w-3.5" />
                $ download Vox.dmg
              </Link>
              <Link
                href="/docs/overview"
                className="inline-flex h-10 items-center gap-2 rounded-sm border border-line-strong bg-panel px-4 font-mono text-[12px] uppercase tracking-[0.06em] text-ink transition-colors hover:text-accent"
              >
                Documentation
                <ArrowUpRight className="h-3 w-3" />
              </Link>
            </div>

            <div className="mt-8 max-w-md">
              <CopyCommand command="bun add -g @voxd/cli@latest" />
              <p className="mt-2 font-mono text-[10px] tracking-wide text-muted">
                local runtime · doctor · warm-up · benchmarks
              </p>
            </div>
          </div>

          {/* Operator window */}
          <div className="self-start overflow-hidden rounded-sm border border-line-strong bg-panel">
            <div className="flex items-center gap-2 border-b border-line bg-canvas px-3 py-2.5">
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span className="ml-auto font-mono text-[11px] text-muted">vox-operator</span>
            </div>
            <div className="p-4 font-mono text-[12.5px] leading-7">
              <div className="text-muted">$ vox perf --client cli</div>
              <div className="text-ink">p50=132ms p95=197ms 35x realtime</div>
              <div className="mt-2.5 text-muted">$ vox transcribe /tmp/sample.wav</div>
              <div className="text-ink">done · 127ms (35x realtime)</div>
              <div className="mt-2.5 text-muted">$ vox warmup --voice parakeet</div>
              <div className="text-ink">warm · ready=412ms</div>
            </div>
          </div>
        </div>
      </section>

      {/* Packages */}
      <section id="packages" className="border-b border-line">
        <div className="mx-auto max-w-6xl px-6 py-20">
          <div className="flex items-baseline justify-between">
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// packages</p>
            <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">5 surfaces</span>
          </div>
          <h2 className="mt-4 max-w-[26ch] text-[clamp(1.5rem,2.6vw,2rem)] font-semibold leading-tight tracking-[-0.02em] text-ink">
            Pick the surface that fits your app.
          </h2>
          <p className="mt-4 max-w-2xl text-[15px] leading-7 text-secondary">
            The same runtime ideas show up in different forms depending on where the voice work lives: in-process Swift, the local companion, the browser bridge, or operator tooling.
          </p>

          <div className="mt-10 rounded-sm border border-line">
            {surfaceCards.map((card, i) => (
              <article
                key={card.title}
                className={`grid items-start grid-cols-1 sm:grid-cols-[minmax(0,180px)_1fr_minmax(0,200px)] ${i === surfaceCards.length - 1 ? "" : "border-b border-line"}`}
              >
                <div className="border-b border-line px-5 py-5 font-mono text-[11px] uppercase tracking-[0.14em] text-muted sm:border-b-0 sm:border-r">
                  {card.eyebrow}
                </div>
                <div className="px-6 py-5">
                  <h3 className="text-[15px] font-semibold tracking-[-0.01em] text-ink">{card.title}</h3>
                  <p className="mt-2 text-[14px] leading-7 text-secondary">{card.body}</p>
                </div>
                <div className="border-t border-line px-5 py-5 sm:border-l sm:border-t-0">
                  <Link
                    href={card.href}
                    className="group inline-flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.14em] text-muted transition-colors hover:text-accent"
                  >
                    → {card.cta}
                    <ArrowUpRight className="h-3 w-3 opacity-50 transition-all group-hover:-translate-y-px group-hover:translate-x-px group-hover:opacity-100" />
                  </Link>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Runtime */}
      <section id="runtime" className="border-b border-line">
        <div className="mx-auto max-w-6xl px-6 py-20">
          <div className="flex items-baseline justify-between">
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// runtime</p>
            <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">4 principles</span>
          </div>
          <h2 className="mt-4 max-w-[30ch] text-[clamp(1.5rem,2.6vw,2rem)] font-semibold leading-tight tracking-[-0.02em] text-ink">
            Embed in apps. Run companion mode for the web and local tools.
          </h2>

          <div className="mt-10 rounded-sm border border-line">
            {featureRows.map(({ idx, title, body }, i) => (
              <article
                key={title}
                className={`grid items-start grid-cols-[3.5rem_1fr] sm:grid-cols-[3.5rem_minmax(0,260px)_1fr] ${i === featureRows.length - 1 ? "" : "border-b border-line"}`}
              >
                <div className="border-r border-line px-3 py-5 text-right font-mono text-[11px] text-muted">{idx}</div>
                <div className="px-6 py-5 font-medium text-ink sm:border-r sm:border-line">{title}</div>
                <p className="col-span-2 border-t border-line px-6 py-5 text-[14px] leading-7 text-secondary sm:col-span-1 sm:border-l-0 sm:border-t-0">
                  {body}
                </p>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Related */}
      <section className="border-b border-line">
        <div className="mx-auto max-w-6xl px-6 py-20">
          <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// related</p>
          <h2 className="mt-4 text-[clamp(1.5rem,2.6vw,2rem)] font-semibold tracking-[-0.02em] text-ink">
            A few related projects.
          </h2>

          <div className="mt-10 grid grid-cols-1 rounded-sm border border-line sm:grid-cols-3">
            {relatedProjects.map((project, i) => (
              <Link
                key={project.name}
                href={project.href}
                target="_blank"
                rel="noreferrer noopener"
                className={`group block px-6 py-5 transition-colors hover:bg-panel ${i === relatedProjects.length - 1 ? "" : "border-b border-line sm:border-b-0 sm:border-r"}`}
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted transition-colors group-hover:text-accent">{project.name}</span>
                  <ArrowUpRight className="h-3.5 w-3.5 text-muted transition-colors group-hover:text-accent" />
                </div>
                <p className="mt-3 text-[14px] leading-7 text-secondary">{project.body}</p>
                <p className="mt-3 font-mono text-[10px] tracking-[0.14em] text-muted">
                  {project.href.replace("https://", "")}
                </p>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* Observability */}
      <section id="perf" className="border-b border-line bg-panel">
        <div className="mx-auto grid max-w-6xl gap-12 px-6 py-20 lg:grid-cols-2 lg:items-start">
          <div>
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// observability</p>
            <h2 className="mt-4 max-w-[22ch] text-[clamp(1.5rem,2.6vw,2rem)] font-semibold leading-tight tracking-[-0.02em] text-ink">
              See where the time goes.
            </h2>
            <p className="mt-4 max-w-md text-[15px] leading-7 text-secondary">
              Every voice request carries stage timings. Slice by client, route, model, and voice.
            </p>
            <div className="mt-7 max-w-xs">
              <CopyCommand command="vox tui" />
            </div>
          </div>
          <div className="overflow-hidden rounded-sm border border-line-strong bg-canvas">
            <div className="flex items-center gap-2 border-b border-line px-3 py-2.5">
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span className="ml-auto font-mono text-[11px] text-muted">vox tui</span>
            </div>
            <ScreenshotLightbox
              src="/tui-dashboard.png"
              alt="Vox dashboard showing performance stats, per-client breakdown, and recent voice activity"
              title="vox tui"
              caption="Performance dashboard with a per-client breakdown and recent voice activity."
            />
          </div>
        </div>
      </section>

      {/* Get started */}
      <section className="border-b border-line">
        <div className="mx-auto max-w-6xl px-6 py-20">
          <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">// install</p>
          <h2 className="mt-4 max-w-[30ch] text-[clamp(1.5rem,2.6vw,2rem)] font-semibold leading-tight tracking-[-0.02em] text-ink">
            Get the companion running for the web and local tools.
          </h2>
          <p className="mt-4 max-w-2xl text-[15px] leading-7 text-secondary">
            Apple apps can embed Vox directly. For browser and shared-process workflows, install the companion app or use the CLI so local web clients and tools can connect to the same warm Vox engine.
          </p>

          <div className="mt-10 grid grid-cols-1 rounded-sm border border-line lg:grid-cols-2">
            <div className="border-b border-line px-6 py-7 lg:border-b-0 lg:border-r">
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted">DOWNLOAD</p>
              <p className="mt-3 text-[14px] leading-7 text-secondary">
                Drag Vox to Applications. The companion starts automatically on login, so web and tooling integrations have a local bridge ready on the machine.
              </p>
              <Link
                href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                className="mt-5 inline-flex h-9 items-center gap-2 rounded-sm border border-line-strong bg-panel px-4 font-mono text-[11px] uppercase tracking-[0.06em] text-ink transition-colors hover:text-accent"
              >
                <Download className="h-3 w-3" />
                Vox.dmg
              </Link>
            </div>
            <div className="px-6 py-7">
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted">CLI</p>
              <div className="mt-3 font-mono text-[12.5px] leading-7">
                <div className="text-muted">$ npx @voxd/cli install</div>
                <div className="text-secondary">Vox Companion installed, LaunchAgent registered</div>
                <div className="mt-2.5 text-muted">$ npx @voxd/cli doctor</div>
                <div className="text-ink">daemon: running</div>
                <div className="text-ink">backend: parakeet</div>
                <div className="text-ink">ready</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer>
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 font-mono text-[11px] uppercase tracking-[0.14em] text-muted sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <span aria-hidden="true" className="inline-block h-2 w-2 rounded-sm bg-accent" />
            <span className="text-ink">vox</span>
            <span>v0.1.0 · local-first</span>
          </div>
          <div className="flex gap-5">
            <Link href="/docs/overview" className="transition-colors hover:text-accent">/docs</Link>
            <Link href="/blog" className="transition-colors hover:text-accent">/blog</Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-2 transition-colors hover:text-accent">
              <Github className="h-3 w-3" />
              /github
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}
