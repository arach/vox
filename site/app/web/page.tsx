import type { Metadata } from "next";
import Link from "next/link";
import { ArrowUpRight, AudioLines, Globe, Radar, ShieldCheck, TerminalSquare, Waypoints } from "lucide-react";
import { CopyCommand, CopyCommandBlock } from "../../components/copy-command";

export const metadata: Metadata = {
  title: "Web SDK · Vox",
  description: "Add local transcription to any web app with @voxd/client and the Vox macOS companion.",
  openGraph: {
    title: "Web SDK · Vox",
    description: "Add local transcription to any web app with @voxd/client and the Vox macOS companion.",
    images: [{ url: "/og/web.png" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Web SDK · Vox",
    description: "Add local transcription to any web app with @voxd/client and the Vox macOS companion.",
    images: ["/og/web.png"],
  },
};

const featureCards = [
  {
    icon: Globe,
    title: "Browser-native API",
    body: "Send a Blob, File, or ArrayBuffer straight from the browser. No backend proxy needed when the companion is present.",
  },
  {
    icon: Radar,
    title: "Probe first",
    body: "Call probe() on page load, fail fast, and degrade cleanly when the companion is not installed or not running.",
  },
  {
    icon: AudioLines,
    title: "Transcribe or align",
    body: "Use transcribe() for local audio and align() when the companion should fetch audio from a URL and return word timings.",
  },
  {
    icon: ShieldCheck,
    title: "Private by default",
    body: "Audio stays on the user's Mac when the companion handles the work. That makes the web SDK a strong fit for internal tools and pro workflows.",
  },
];

const sdkSteps = [
  ["npm install @voxd/client", "Add the browser SDK to your web app."],
  ["const client = createVoxdClient()", "Create the local bridge client."],
  ["await client.probe()", "Check whether the companion is available on this Mac."],
  ["await client.transcribe({ audio: blob })", "Send captured audio to the local runtime and get transcript text plus timing data."],
];

export default function WebSdkPage() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <header className="sticky top-0 z-50 border-b border-line bg-canvas/92 px-6 backdrop-blur-xl sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-6xl items-center justify-between py-3">
          <div className="flex items-center gap-3 font-mono text-[12px] uppercase tracking-[0.14em]">
            <Link href="/" className="flex items-center gap-2 text-ink">
              <img src="/logo.svg" alt="Vox" className="h-5 w-5" />
              Vox
            </Link>
            <span className="text-muted">/</span>
            <span className="text-muted">Web SDK</span>
          </div>

          <div className="flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.12em] text-muted">
            <Link href="/docs/web-integration" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Docs
            </Link>
            <Link href="/blog" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Blog
            </Link>
            <Link href="https://github.com/arach/vox/tree/main/packages/web-client" target="_blank" rel="noreferrer noopener" className="rounded-md px-3 py-2 transition-colors hover:bg-wave hover:text-ink">
              Source
            </Link>
          </div>
        </div>
      </header>

      <section className="relative overflow-hidden px-6 pb-20 pt-16 sm:px-8 lg:px-12">
        <div className="hero-mesh pointer-events-none absolute inset-0" />
        <div className="hero-grid pointer-events-none absolute inset-x-0 top-0 h-[38rem]" />
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-12 py-12 lg:grid-cols-[1.05fr_0.95fr] lg:items-start">
            <div>
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-accent">Web SDK</p>
              <h1 className="mt-5 max-w-[13ch] font-display text-4xl leading-[1.04] tracking-[-0.04em] sm:text-6xl lg:text-[5.4rem]">
                Local transcription for apps that already live in the browser.
              </h1>
              <p className="mt-8 max-w-2xl text-base leading-8 text-secondary sm:text-lg">
                <code className="rounded bg-wave px-2 py-1 font-mono text-[0.95em] text-accent">@voxd/client</code> gives web apps a direct path to the Vox companion on the user&apos;s Mac: probe availability, transcribe blobs, align remote audio, and fall back gracefully when local runtime is unavailable.
              </p>

              <div className="mt-10 flex flex-col items-start gap-4 sm:flex-row sm:items-center">
                <CopyCommand command="npm install @voxd/client" />
                <Link
                  href="/docs/web-integration"
                  className="group inline-flex h-11 items-center gap-2 rounded-[3px_8px_8px_3px] border border-line-strong px-5 font-mono text-[12px] uppercase tracking-[0.1em] text-secondary transition-all hover:border-accent/50 hover:bg-wave hover:text-ink"
                >
                  Read integration docs
                  <ArrowUpRight className="h-3.5 w-3.5 opacity-40 transition-all group-hover:opacity-70 group-hover:-translate-y-px group-hover:translate-x-px" />
                </Link>
              </div>
            </div>

            <div className="signal-panel rounded-xl border border-line-strong bg-panel p-5 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">SDK flow</span>
                <TerminalSquare className="h-4 w-4 text-accent" />
              </div>
              <div className="mt-4 rounded-lg border border-line bg-canvas p-4 font-mono text-[12px] leading-6 text-secondary">
                <div className="text-muted">import {"{ createVoxdClient }"} from "@voxd/client"</div>
                <div className="mt-3 text-ink">const client = createVoxdClient()</div>
                <div className="text-ink">if (await client.probe()) {"{"}</div>
                <div className="pl-4 text-ink">await client.transcribe({"{"} audio: blob {"}"})</div>
                <div className="text-ink">{"}"}</div>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {["probe()", "transcribe()", "align()", "launch()"].map((item) => (
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

      <section className="border-y border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="mb-14">
            <h2 className="max-w-[18ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-5xl">
              A clean browser story, without pretending the browser owns the runtime.
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
      </section>

      <section className="px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-12 lg:grid-cols-[0.88fr_1.12fr]">
            <div>
              <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-accent">How it works</p>
              <h2 className="mt-4 max-w-[16ch] font-display text-3xl leading-tight tracking-[-0.03em] sm:text-5xl">
                Install the package, detect the companion, then choose the right local path.
              </h2>
              <p className="mt-6 max-w-md text-[15px] leading-7 text-secondary">
                The package is intentionally narrow. It does not try to own media capture or browser permissions. It just gives your app a clean bridge to the local Vox runtime.
              </p>
            </div>

            <div className="space-y-3">
              {sdkSteps.map(([command, label]) => (
                <CopyCommandBlock key={command} command={command} label={label} />
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="border-t border-line bg-panel px-6 py-20 sm:px-8 lg:px-12">
        <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[1.05fr_0.95fr]">
          <div className="rounded-xl border border-line-strong bg-canvas p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
            <p className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Design constraints</p>
            <h2 className="mt-4 max-w-[16ch] font-display text-3xl italic leading-tight tracking-[-0.03em] sm:text-4xl">
              The browser SDK should stay boring where boring is correct.
            </h2>
            <div className="mt-6 grid gap-5 text-[15px] leading-7 text-secondary">
              <p>It should not hide runtime availability. Call <code className="rounded bg-wave px-2 py-1 font-mono text-[0.95em] text-accent">probe()</code>, show a clear install or launch path, and degrade when the companion is unavailable.</p>
              <p>It should not pretend every app wants the same audio path. Use <code className="rounded bg-wave px-2 py-1 font-mono text-[0.95em] text-accent">transcribe()</code> for local blobs and <code className="rounded bg-wave px-2 py-1 font-mono text-[0.95em] text-accent">align()</code> when the runtime should fetch audio itself.</p>
              <p>And it should preserve the local-first story: audio stays on the Mac, while the web app gets a small, typed bridge instead of another heavyweight backend dependency.</p>
            </div>
          </div>

          <div className="rounded-xl border border-line-strong bg-canvas p-6 shadow-[0_24px_80px_rgba(0,0,0,0.35)]">
            <p className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">Next stops</p>
            <div className="mt-6 grid gap-4">
              <Link
                href="/docs/web-integration"
                className="group rounded-lg border border-line bg-panel px-5 py-4 transition-all hover:border-accent/50 hover:bg-wave"
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">Guide</span>
                  <ArrowUpRight className="h-3.5 w-3.5 text-muted transition-all group-hover:text-accent group-hover:-translate-y-px group-hover:translate-x-px" />
                </div>
                <p className="mt-2 text-[15px] leading-7 text-secondary">Open the web integration docs and copy the full install and probe flow.</p>
              </Link>

              <Link
                href="https://github.com/arach/vox/tree/main/packages/web-client"
                target="_blank"
                rel="noreferrer noopener"
                className="group rounded-lg border border-line bg-panel px-5 py-4 transition-all hover:border-accent/50 hover:bg-wave"
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">Package</span>
                  <ArrowUpRight className="h-3.5 w-3.5 text-muted transition-all group-hover:text-accent group-hover:-translate-y-px group-hover:translate-x-px" />
                </div>
                <p className="mt-2 text-[15px] leading-7 text-secondary">Inspect the browser client source and current API surface in the repo.</p>
              </Link>

              <Link
                href="https://github.com/arach/vox/releases/latest/download/Vox.dmg"
                className="group rounded-lg border border-line bg-panel px-5 py-4 transition-all hover:border-accent/50 hover:bg-wave"
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">Companion</span>
                  <ArrowUpRight className="h-3.5 w-3.5 text-muted transition-all group-hover:text-accent group-hover:-translate-y-px group-hover:translate-x-px" />
                </div>
                <p className="mt-2 text-[15px] leading-7 text-secondary">Download the macOS companion that the browser SDK probes and talks to locally.</p>
              </Link>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
