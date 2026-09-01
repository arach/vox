import { readdir } from "node:fs/promises";
import config from "../dewey.config.ts";

type Doc = {
  id: string;
  title: string;
  description?: string;
  content: string;
};

const root = new URL("../", import.meta.url);
const docsRoot = new URL("docs/", root);
const checkOnly = Bun.argv.includes("--check");

function parseMarkdown(id: string, source: string): Doc {
  let content = source.trim();
  let title: string | undefined;
  let description: string | undefined;

  if (content.startsWith("---\n")) {
    const end = content.indexOf("\n---\n", 4);
    if (end !== -1) {
      const frontmatter = content.slice(4, end);
      title = frontmatter.match(/^title:\s*(.+)$/m)?.[1]?.trim();
      description = frontmatter.match(/^description:\s*(.+)$/m)?.[1]?.trim();
      content = content.slice(end + 5).trim();
    }
  }

  title ??= content.match(/^#\s+(.+)$/m)?.[1]?.trim();
  title ??= id.split("-").map((part) => part[0]?.toUpperCase() + part.slice(1)).join(" ");

  return { id, title, description, content };
}

function summary(doc: Doc): string {
  const paragraphs = doc.content
    .replace(/^#\s+.+$/m, "")
    .split(/\n\s*\n/)
    .map((value) => value.replace(/^>\s?/gm, "").trim())
    .filter((value) => value && !value.startsWith("#") && !value.startsWith("```"));
  return (doc.description ?? paragraphs[0] ?? "").replace(/\s+/g, " ").slice(0, 360);
}

const docs: Doc[] = [];
for (const id of config.agent.sections) {
  const file = Bun.file(new URL(`${id}.md`, docsRoot));
  if (await file.exists()) docs.push(parseMarkdown(id, await file.text()));
}

const agentDirectory = new URL("agent/", docsRoot);
const agentNames = (await readdir(agentDirectory))
  .filter((name) => name.endsWith(".agent.md"))
  .sort();
const agentDocs: Doc[] = [];
for (const name of agentNames) {
  const id = name.replace(/\.agent\.md$/, "");
  agentDocs.push(parseMarkdown(id, await Bun.file(new URL(name, agentDirectory)).text()));
}

const llms = [
  `# ${config.project.name}`,
  "",
  `> ${config.project.tagline}`,
  "",
  "## Choose a surface",
  "",
  "- Apple app process: VoxCore + VoxEngine (+ optional VoxAppleSpeech)",
  "- Bun or Node tool: voxd + @voxd/sdk",
  "- Browser app: Vox Companion + @voxd/client",
  "- Operator workflow: @voxd/cli",
  "",
  "## Documentation",
  "",
  ...docs.map((doc) => `- [${doc.title}](/docs/${doc.id}): ${summary(doc)}`),
  "",
  "## Agent handoff",
  "",
  "Use /docs/agents for canonical source routing. Use /llms-full.txt for complete human docs plus compact agent briefs.",
  "",
  "Generated from dewey.config.ts and docs/ by scripts/generate-agent-artifacts.ts.",
  "",
].join("\n");

const fullSections = docs.flatMap((doc) => [
  `# ${doc.title}`,
  "",
  `Source: /docs/${doc.id}`,
  "",
  doc.content,
  "",
]);
const agentSections = agentDocs.flatMap((doc) => [
  `# ${doc.title}`,
  "",
  `Source: docs/agent/${doc.id}.agent.md`,
  "",
  doc.content,
  "",
]);
const llmsFull = [
  `# ${config.project.name}: complete documentation handoff`,
  "",
  `> ${config.project.tagline}`,
  "",
  "## Human documentation",
  "",
  ...fullSections,
  "## Compact agent briefs",
  "",
  ...agentSections,
  "Generated from dewey.config.ts and docs/ by scripts/generate-agent-artifacts.ts.",
  "",
].join("\n");

const docsJson = `${JSON.stringify({
  project: config.project.name,
  version: config.project.version,
  generatedBy: "scripts/generate-agent-artifacts.ts",
  sections: docs,
  agentBriefs: agentDocs,
}, null, 2)}\n`;

const outputs = new Map([
  ["llms.txt", llms],
  ["llms-full.txt", llmsFull],
  ["docs.json", docsJson],
]);

let outdated = false;
for (const [path, content] of outputs) {
  const target = new URL(path, root);
  const current = await Bun.file(target).exists() ? await Bun.file(target).text() : "";
  if (current === content) continue;
  outdated = true;
  if (checkOnly) {
    console.error(`${path} is out of date. Run bun run docs:generate.`);
  } else {
    await Bun.write(target, content);
    console.log(`generated ${path}`);
  }
}

if (checkOnly && outdated) process.exit(1);
if (checkOnly) console.log("agent artifacts are current");
