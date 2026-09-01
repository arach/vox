import type { Metadata } from "next";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { CopyCommand } from "../../components/copy-command";
import catalog from "../../public/data/models.json";

export const metadata: Metadata = {
  title: "Models · Vox",
  description: "Published dictation catalog for Vox: Apple SpeechTranscriber, Parakeet, Moonshine, OpenAI, mlx-audio, and plugins.",
  openGraph: {
    title: "Models · Vox",
    description: "The dictation catalog Vox publishes at /data/models.json.",
    images: [{ url: "/og.png" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Models · Vox",
    description: "The dictation catalog Vox publishes at /data/models.json.",
    images: ["/og.png"],
  },
};

type CatalogModel = {
  id: string;
  name: string;
  family: string;
  vendor?: string;
  runtime?: string;
  status?: string;
  default?: boolean;
  plugin?: string;
  languages?: string;
  notes?: string;
  platforms?: string[];
  architectures?: string[];
  capabilities?: {
    fileTranscription: boolean;
    liveTranscription: boolean;
    onDevice: boolean;
    wordTimestamps: boolean;
  };
};

type CatalogPlugin = {
  id: string;
  name: string;
  kind: string;
  status?: string;
  notes?: string;
  install?: { kind: string; id?: string; package?: string };
};

const models = catalog.models as CatalogModel[];
const plugins = (catalog.plugins ?? []) as CatalogPlugin[];

function statusLabel(model: CatalogModel) {
  if (model.default) return "default";
  if (model.plugin) return "plugin";
  return model.status ?? "ready";
}

export default function ModelsPage() {
  return (
    <main className="min-h-screen bg-canvas text-ink">
      <header className="border-b border-line">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-3">
            <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm bg-accent" />
            <span className="text-[15px] font-medium tracking-tight text-ink">Vox</span>
          </Link>
          <nav aria-label="Primary" className="flex items-center gap-1 font-mono text-[11px] uppercase tracking-[0.14em] text-muted">
            <Link href="/docs/models" className="px-2.5 py-1.5 transition-colors hover:text-accent">Docs</Link>
            <Link href="/download" className="px-2.5 py-1.5 transition-colors hover:text-accent">Download</Link>
            <Link href="/minivox" className="px-2.5 py-1.5 transition-colors hover:text-accent">Minivox</Link>
            <Link href="/data/models.json" className="px-2.5 py-1.5 transition-colors hover:text-accent">JSON</Link>
          </nav>
        </div>
      </header>

      <section className="border-b border-line">
        <div className="mx-auto grid max-w-6xl gap-12 px-6 py-20 lg:grid-cols-[1.15fr_0.85fr]">
          <div>
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">{"// catalog"}</p>
            <h1 className="mt-5 max-w-[16ch] text-[clamp(1.75rem,3.8vw,2.75rem)] font-medium leading-[1.15] tracking-[-0.03em] text-ink">
              Dictation models, published as data<span className="text-accent">.</span>
            </h1>
            <p className="mt-6 max-w-xl text-[15px] leading-7 text-secondary">
              Vox reads <code className="font-mono text-[13px] text-ink">https://voxd.cc/data/models.json</code>.
              Built-in families load without extra install. New families ship as plugins.
            </p>
            <div className="mt-8 max-w-md">
              <CopyCommand command="vox models catalog" />
              <p className="mt-3 font-mono text-[10px] tracking-wide text-muted">
                catalog v{catalog.version} · updated {catalog.updatedAt}
              </p>
            </div>
          </div>
          <div className="self-start overflow-hidden rounded-sm border border-line-strong bg-panel">
            <div className="flex items-center gap-2 border-b border-line bg-canvas px-3 py-2.5">
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span aria-hidden="true" className="inline-block h-1.5 w-1.5 rounded-full bg-line-strong" />
              <span className="ml-auto font-mono text-[11px] text-muted">vox plugins</span>
            </div>
            <div className="p-4 font-mono text-[12.5px] leading-7">
              <div className="text-muted">$ vox plugins list</div>
              <div className="text-ink">mlx-vlm asr available bundle</div>
              <div className="mt-2.5 text-muted">$ vox plugins install mlx-vlm</div>
              <div className="text-ink">Installed plugin mlx-vlm</div>
              <div className="mt-2.5 text-muted">$ vox transcribe file --model gemma-4-e2b-it clip.wav</div>
              <div className="text-ink">restart voxd first, then transcribe</div>
            </div>
          </div>
        </div>
      </section>

      <section className="border-b border-line">
        <div className="mx-auto max-w-6xl px-6 py-16">
          <div className="flex items-baseline justify-between gap-4">
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">{"// models"}</p>
            <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-muted">{models.length} entries</span>
          </div>
          <div className="mt-6 overflow-hidden rounded-sm border border-line">
            <div className="hidden grid-cols-[minmax(0,1.4fr)_minmax(0,0.8fr)_minmax(0,0.7fr)_minmax(0,0.6fr)] border-b border-line bg-panel font-mono text-[10px] uppercase tracking-[0.14em] text-muted sm:grid">
              <div className="px-4 py-3">Id</div>
              <div className="border-l border-line px-4 py-3">Family</div>
              <div className="border-l border-line px-4 py-3">Runtime</div>
              <div className="border-l border-line px-4 py-3">Status</div>
            </div>
            {models.map((model, index) => (
              <article
                key={model.id}
                className={`grid gap-1 px-4 py-4 sm:grid-cols-[minmax(0,1.4fr)_minmax(0,0.8fr)_minmax(0,0.7fr)_minmax(0,0.6fr)] sm:items-baseline sm:gap-0 ${index === models.length - 1 ? "" : "border-b border-line"}`}
              >
                <div>
                  <p className="font-mono text-[13px] text-ink">{model.id}</p>
                  <p className="mt-1 text-[13px] leading-6 text-secondary">{model.name}</p>
                  {model.capabilities ? (
                    <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.1em] text-muted">
                      {model.capabilities.onDevice ? "on-device" : "remote"}
                      {model.capabilities.fileTranscription ? " · file" : ""}
                      {model.capabilities.liveTranscription ? " · live" : " · finalized"}
                      {model.capabilities.wordTimestamps ? " · word times" : ""}
                    </p>
                  ) : null}
                  {model.notes ? <p className="mt-1 text-[12px] leading-6 text-muted">{model.notes}</p> : null}
                </div>
                <p className="font-mono text-[11px] text-muted sm:border-l sm:border-line sm:px-4">{model.family}</p>
                <p className="font-mono text-[11px] text-muted sm:border-l sm:border-line sm:px-4">{model.runtime ?? "—"}</p>
                <p className="font-mono text-[11px] uppercase tracking-[0.12em] text-accent sm:border-l sm:border-line sm:px-4">
                  {statusLabel(model)}
                </p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="border-b border-line bg-panel">
        <div className="mx-auto max-w-6xl px-6 py-16">
          <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted">{"// plugins"}</p>
          <h2 className="mt-4 max-w-[28ch] text-[clamp(1.4rem,2.4vw,1.85rem)] font-semibold leading-tight tracking-[-0.02em] text-ink">
            New families install as plugins.
          </h2>
          <p className="mt-4 max-w-2xl text-[15px] leading-7 text-secondary">
            A plugin is an external JSON-RPC provider. Catalog refresh does not run it. Install writes <code className="font-mono text-[13px] text-ink">~/.vox/plugins/&lt;id&gt;/provider.json</code>, then restart voxd.
          </p>
          <div className="mt-8 overflow-hidden rounded-sm border border-line bg-canvas">
            {plugins.map((plugin, index) => (
              <article
                key={plugin.id}
                className={`px-5 py-5 ${index === plugins.length - 1 ? "" : "border-b border-line"}`}
              >
                <div className="flex flex-wrap items-baseline justify-between gap-3">
                  <h3 className="font-mono text-[13px] text-ink">{plugin.id}</h3>
                  <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-muted">
                    {plugin.kind} · {plugin.install?.kind ?? "command"}
                  </span>
                </div>
                <p className="mt-2 text-[14px] leading-7 text-secondary">{plugin.notes ?? plugin.name}</p>
                <div className="mt-4 max-w-md">
                  <CopyCommand command={`vox plugins install ${plugin.id}`} />
                </div>
              </article>
            ))}
          </div>
          <Link
            href="/docs/models"
            className="mt-8 inline-flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.14em] text-muted transition-colors hover:text-accent"
          >
            Models and plugins guide
            <ArrowUpRight className="h-3 w-3" />
          </Link>
        </div>
      </section>
    </main>
  );
}
