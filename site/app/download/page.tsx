import type { Metadata } from "next";
import Link from "next/link";
import { ArrowUpRight, CheckCircle2, Download, Github, ShieldCheck, TerminalSquare } from "lucide-react";
import { CopyCommand } from "../../components/copy-command";

const dmgUrl = "https://github.com/arach/vox/releases/latest/download/Vox.dmg";

export const metadata: Metadata = {
  title: "Download Vox",
  description: "Download the signed and notarized Vox Companion app for macOS.",
  openGraph: {
    title: "Download Vox",
    description: "Download the signed and notarized Vox Companion app for macOS.",
    images: [{ url: "/og.png" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Download Vox",
    description: "Download the signed and notarized Vox Companion app for macOS.",
    images: ["/og.png"],
  },
};

const checks = [
  "Signed and notarized DMG from the latest GitHub Release",
  "Bundles Vox.app, voxd, and the separate voxttsd speech worker",
  "Works with the CLI, @voxd/sdk, and @voxd/client",
];

export default function DownloadPage() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <header className="border-b border-line">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-3">
            <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm bg-accent" />
            <span className="text-[15px] font-medium tracking-tight text-ink">Vox</span>
          </Link>
          <nav className="flex flex-wrap items-center gap-1 font-mono text-[11px] uppercase tracking-[0.14em] text-muted">
            <Link href="/docs/overview" className="px-2.5 py-1.5 transition-colors hover:text-accent">Docs</Link>
            <Link href="/web" className="px-2.5 py-1.5 transition-colors hover:text-accent">Web SDK</Link>
            <Link href="/blog" className="px-2.5 py-1.5 transition-colors hover:text-accent">Blog</Link>
            <Link href="https://github.com/arach/vox" target="_blank" rel="noreferrer noopener" className="px-2.5 py-1.5 transition-colors hover:text-accent">GitHub</Link>
          </nav>
        </div>
      </header>

      <section className="border-b border-line">
        <div className="mx-auto grid max-w-6xl gap-12 px-6 py-20 lg:grid-cols-[1.15fr_0.85fr] lg:items-start">
          <div>
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">{"// download"}</p>
            <h1 className="mt-5 max-w-[16ch] text-[clamp(2rem,5vw,4rem)] font-medium leading-[1.05] tracking-[-0.04em] text-ink">
              Install Vox Companion for macOS<span className="text-accent">.</span>
            </h1>
            <p className="mt-6 max-w-xl text-[15px] leading-7 text-secondary">
              Vox Companion gives local web apps, the CLI, and Hudson-powered native surfaces a shared voice runtime on your Mac. Install once, then connect from the browser SDK or operator tools.
            </p>

            <div className="mt-9 flex flex-wrap items-center gap-3">
              <Link
                href={dmgUrl}
                className="inline-flex h-11 items-center gap-2 rounded-sm border border-accent bg-accent px-5 font-mono text-[12px] font-medium uppercase tracking-[0.06em] text-canvas"
              >
                <Download className="h-3.5 w-3.5" />
                Download Vox.dmg
              </Link>
              <Link
                href="https://github.com/arach/vox/releases/latest"
                target="_blank"
                rel="noreferrer noopener"
                className="inline-flex h-11 items-center gap-2 rounded-sm border border-line-strong bg-panel px-4 font-mono text-[12px] uppercase tracking-[0.06em] text-ink transition-colors hover:text-accent"
              >
                Release notes
                <ArrowUpRight className="h-3 w-3" />
              </Link>
            </div>
          </div>

          <div className="rounded-sm border border-line-strong bg-panel p-6">
            <div className="flex items-center justify-between border-b border-line pb-4">
              <span className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted">Installer</span>
              <ShieldCheck className="h-4 w-4 text-accent" />
            </div>
            <div className="mt-5 space-y-4">
              {checks.map((check) => (
                <div key={check} className="flex gap-3 text-[14px] leading-6 text-secondary">
                  <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
                  <span>{check}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="border-b border-line">
        <div className="mx-auto grid max-w-6xl gap-px px-6 py-20 lg:grid-cols-2">
          <div className="border border-line bg-panel p-8">
            <div className="mb-5 flex items-center gap-3">
              <Download className="h-4 w-4 text-muted" />
              <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">Mac app</span>
            </div>
            <p className="text-[14px] leading-7 text-secondary">
              Open the DMG, drag Vox to Applications, and launch it from there. The menu bar app manages the companion runtime used by local web and CLI clients.
            </p>
          </div>

          <div className="border border-line bg-panel p-8">
            <div className="mb-5 flex items-center gap-3">
              <TerminalSquare className="h-4 w-4 text-muted" />
              <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-muted">CLI</span>
            </div>
            <CopyCommand command="npm install -g @voxd/cli@latest" />
            <p className="mt-4 text-[14px] leading-7 text-secondary">
              Use the CLI for doctor checks, warm-up, benchmarks, logs, and speech synthesis from terminal workflows.
            </p>
          </div>
        </div>
      </section>

      <footer>
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 font-mono text-[11px] uppercase tracking-[0.14em] text-muted sm:flex-row sm:items-center sm:justify-between">
          <span>voxd.cc/download</span>
          <div className="flex gap-5">
            <Link href="/docs/quickstart" className="transition-colors hover:text-accent">/quickstart</Link>
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
