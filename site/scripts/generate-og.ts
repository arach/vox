import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { execFileSync } from "child_process";

const docPages = [
  { id: "overview", title: "Overview", group: "Getting Started" },
  { id: "quickstart", title: "Quickstart", group: "Getting Started" },
  { id: "observability", title: "Observability", group: "Core" },
  { id: "architecture", title: "Architecture", group: "Core" },
  { id: "api", title: "API", group: "For Agents" },
  { id: "sdk", title: "SDK", group: "For Agents" },
  { id: "skill", title: "Operator Playbook", group: "For Agents" },
  { id: "runtime", title: "Runtime", group: "Runtime" },
];

const siteRoot = process.cwd();
const publicRoot = join(siteRoot, "public");
const docsOgRoot = join(publicRoot, "og", "docs");
const tempRoot = mkdtempSync(join(tmpdir(), "vox-og-"));

function shellEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderDocTemplate(title: string, eyebrow: string, detail: string) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet" />
    <style>
      :root {
        --bg: #09090b;
        --panel: rgba(20, 20, 22, 0.94);
        --ink: #fafafa;
        --muted: #a1a1aa;
        --soft: #71717a;
        --accent: #34d399;
        --accent-strong: #10b981;
        --line: rgba(255, 255, 255, 0.1);
        --grid: rgba(255, 255, 255, 0.045);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        width: 1200px;
        height: 630px;
        overflow: hidden;
        position: relative;
        background:
          radial-gradient(circle at 8% 14%, rgba(52, 211, 153, 0.14), transparent 24rem),
          radial-gradient(circle at 92% 86%, rgba(52, 211, 153, 0.08), transparent 20rem),
          var(--bg);
        color: var(--ink);
        font-family: "Inter", sans-serif;
      }

      .grid {
        position: absolute;
        inset: 0;
        background-image:
          linear-gradient(to right, var(--grid) 1px, transparent 1px),
          linear-gradient(to bottom, var(--grid) 1px, transparent 1px);
        background-size: 48px 48px;
        opacity: 0.18;
      }

      .grid::before,
      .grid::after {
        content: "";
        position: absolute;
        inset: 0;
        background-image:
          linear-gradient(to right, var(--grid) 1px, transparent 1px),
          linear-gradient(to bottom, var(--grid) 1px, transparent 1px);
        background-size: 48px 48px;
      }

      .grid::before {
        opacity: 0.5;
        mask-image: radial-gradient(circle at 48px 48px, black 0, black 19rem, transparent 34rem);
      }

      .grid::after {
        opacity: 0.36;
        mask-image: radial-gradient(circle at calc(100% - 48px) calc(100% - 48px), black 0, black 18rem, transparent 34rem);
      }

      .corner {
        position: absolute;
        width: 96px;
        height: 96px;
        opacity: 0.72;
      }

      .corner::before,
      .corner::after {
        content: "";
        position: absolute;
      }

      .corner::before {
        width: 96px;
        height: 2px;
        background: linear-gradient(90deg, var(--accent), transparent);
      }

      .corner::after {
        width: 2px;
        height: 96px;
        background: linear-gradient(180deg, var(--accent), transparent);
      }

      .corner.tl { top: 48px; left: 48px; }
      .corner.br { right: 48px; bottom: 48px; transform: rotate(180deg); }

      .wrap {
        position: relative;
        height: 100%;
        padding: 74px 96px 68px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
      }

      .wordmark {
        color: var(--ink);
        font-family: "JetBrains Mono", monospace;
        font-size: 38px;
        font-weight: 700;
        letter-spacing: -0.04em;
        text-transform: uppercase;
      }

      .eyebrow {
        margin-top: 40px;
        color: var(--accent);
        font-family: "JetBrains Mono", monospace;
        font-size: 16px;
        font-weight: 700;
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }

      h1 {
        margin: 22px 0 0;
        max-width: 840px;
        font-family: "Instrument Serif", serif;
        font-size: 86px;
        line-height: 0.92;
        letter-spacing: -0.05em;
        font-weight: 400;
      }

      .detail {
        color: var(--muted);
        font-family: "JetBrains Mono", monospace;
        font-size: 20px;
        line-height: 1.7;
        letter-spacing: 0.1em;
        text-transform: uppercase;
      }

      .footer {
        display: flex;
        justify-content: space-between;
        align-items: flex-end;
        gap: 24px;
      }

      .panel {
        width: 420px;
        padding: 22px 24px 20px;
        border: 1px solid var(--line);
        border-radius: 18px;
        background: var(--panel);
        box-shadow: 0 24px 70px rgba(0, 0, 0, 0.35);
      }

      .panel-label {
        color: var(--soft);
        font-family: "JetBrains Mono", monospace;
        font-size: 14px;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .panel-body {
        margin-top: 12px;
        color: var(--ink);
        font-family: "JetBrains Mono", monospace;
        font-size: 16px;
        font-weight: 500;
        line-height: 1.8;
      }

      .panel-accent {
        height: 4px;
        margin-top: 18px;
        border-radius: 999px;
        background: linear-gradient(90deg, transparent, var(--accent) 28%, var(--accent-strong) 72%, transparent);
      }

      .site {
        color: var(--muted);
        font-family: "JetBrains Mono", monospace;
        font-size: 18px;
        font-weight: 500;
      }
    </style>
  </head>
  <body>
    <div class="grid"></div>
    <div class="corner tl"></div>
    <div class="corner br"></div>
    <div class="wrap">
      <div>
        <div class="wordmark">Vox</div>
        <div class="eyebrow">${shellEscape(eyebrow)}</div>
        <h1>${shellEscape(title)}</h1>
      </div>
      <div class="footer">
        <div class="detail">${shellEscape(detail)}</div>
        <div class="panel">
          <div class="panel-label">Docs</div>
          <div class="panel-body">AI-ready handoff<br />Swift runtime + Bun CLI + TS SDK<br />Operator-first observability</div>
          <div class="panel-accent"></div>
        </div>
      </div>
    </div>
  </body>
</html>`;
}

function renderToPng(htmlPath: string, outputPath: string) {
  execFileSync("bun", ["x", "@arach/og", htmlPath, "-o", outputPath], {
    cwd: siteRoot,
    stdio: "inherit",
  });
}

function writeTempHtml(name: string, html: string) {
  const output = join(tempRoot, `${name}.html`);
  writeFileSync(output, html, "utf8");
  return output;
}

try {
  mkdirSync(docsOgRoot, { recursive: true });

  renderToPng(join(siteRoot, "og-template.html"), join(publicRoot, "og.png"));

  const docsIndexHtml = writeTempHtml(
    "docs-index",
    renderDocTemplate("Documentation for the Vox runtime.", "Docs", "Native macOS. Private. Observable."),
  );
  renderToPng(docsIndexHtml, join(publicRoot, "og", "docs.png"));

  for (const page of docPages) {
    const html = writeTempHtml(
      page.id,
      renderDocTemplate(page.title, `${page.group} / Docs`, "Swift runtime. Bun CLI. TypeScript SDK."),
    );
    renderToPng(html, join(docsOgRoot, `${page.id}.png`));
  }
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}
