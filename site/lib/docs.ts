import { readFileSync } from "fs";
import { join } from "path";

const docPages = [
  { id: "overview", title: "Overview", file: "overview.md", group: "Getting Started" },
  { id: "quickstart", title: "Quickstart", file: "quickstart.md", group: "Getting Started" },
  { id: "runtime", title: "Runtime", file: "runtime.md", group: "Runtime" },
  { id: "sdk", title: "SDK", file: "sdk.md", group: "Runtime" },
  { id: "observability", title: "Observability", file: "observability.md", group: "Runtime" },
  { id: "architecture", title: "Architecture", file: "architecture.md", group: "Reference" },
  { id: "api", title: "API", file: "api.md", group: "Reference" },
  { id: "skill", title: "Operator Playbook", file: "skill.md", group: "Reference" },
] as const;

export function getDocPages() {
  return [...docPages];
}

function docsRoot(): string {
  return join(process.cwd(), "..", "docs");
}

export function getSerializedDocs(): Record<string, string> {
  return Object.fromEntries(
    docPages.map((page) => [page.id, readFileSync(join(docsRoot(), page.file), "utf8")]),
  );
}

export function getDocsNavigation() {
  const groups = new Map<string, Array<{ id: string; title: string }>>();

  for (const page of docPages) {
    const existing = groups.get(page.group) ?? [];
    existing.push({ id: page.id, title: page.title });
    groups.set(page.group, existing);
  }

  return [...groups.entries()].map(([title, items]) => ({ title, items }));
}

export function getPageId(slug?: string[]): string {
  const candidate = slug?.[0] ?? "overview";
  return docPages.some((page) => page.id === candidate) ? candidate : "overview";
}

export function getPageContent(id: string) {
  return docPages.find((page) => page.id === id) ?? docPages[0];
}
