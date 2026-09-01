import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { getVoxHome } from "@voxd/sdk";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CATALOG_URL = "https://voxd.cc/data/models.json";
const ALLOWED_LAUNCHERS = new Set(["node", "bun", "npx", "bunx", "uv", "uvx", "python3", "python"]);
const PLUGIN_ID_PATTERN = /^[a-z0-9][a-z0-9._-]*$/;

export type CatalogPlugin = {
  id: string;
  kind: string;
  name: string;
  status?: string;
  command?: string[];
  env?: Record<string, string>;
  install?: { kind: string; id?: string; package?: string };
  notes?: string;
};

export type CatalogModel = {
  id: string;
  plugin?: string;
  name?: string;
};

export type CatalogDocument = {
  version: number;
  updatedAt: string;
  models: CatalogModel[];
  plugins: CatalogPlugin[];
};

export function pluginsDirectory(home = getVoxHome()): string {
  return join(home, "plugins");
}

export function validatePluginId(id: string): void {
  if (!PLUGIN_ID_PATTERN.test(id) || id.includes("..")) {
    throw new Error(`Plugin id '${id}' is not allowed.`);
  }
}

export function pluginDirectory(id: string, home = getVoxHome()): string {
  validatePluginId(id);
  return join(pluginsDirectory(home), id);
}

export function bundledPluginPath(id: string): string | null {
  validatePluginId(id);
  const candidates = [
    join(MODULE_DIR, "../plugins", `${id}.mjs`),
    join(MODULE_DIR, "plugins", `${id}.mjs`),
  ];
  return candidates.find((path) => existsSync(path)) ?? null;
}

export function validatePluginCommand(command: string[]): void {
  if (command.length === 0 || !command[0]) {
    throw new Error("Plugin command is empty.");
  }
  const launcher = command[0].split(/[/\\]/).pop() ?? command[0];
  if (!ALLOWED_LAUNCHERS.has(launcher)) {
    throw new Error(`Plugin command launcher '${launcher}' is not allowed.`);
  }
  for (const argument of command) {
    if (/[\n;|&`$]/.test(argument) || argument.includes("$(")) {
      throw new Error(`Plugin command argument is not allowed: ${argument}`);
    }
  }
}

export async function loadCatalogDocument(): Promise<CatalogDocument> {
  const envURL = process.env.VOX_MODEL_CATALOG_URL?.trim();
  const cachePath = join(getVoxHome(), "cache", "models-catalog.json");
  const repoPath = join(MODULE_DIR, "../../../data/models.json");
  const paths = [envURL && !envURL.startsWith("http") ? envURL : null, cachePath, repoPath].filter(
    (value): value is string => Boolean(value),
  );

  for (const path of paths) {
    if (!existsSync(path)) continue;
    return parseCatalog(JSON.parse(readFileSync(path, "utf8")));
  }

  const url = envURL && envURL.startsWith("http") ? envURL : DEFAULT_CATALOG_URL;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Model catalog request failed with HTTP ${response.status}.`);
  }
  return parseCatalog(await response.json());
}

export function parseCatalog(raw: unknown): CatalogDocument {
  const record = isRecord(raw) ? raw : {};
  const models = Array.isArray(record.models) ? record.models : [];
  const plugins = Array.isArray(record.plugins) ? record.plugins : [];
  return {
    version: Number(record.version ?? 1),
    updatedAt: String(record.updatedAt ?? ""),
    models: models.map((entry) => {
      const fields = isRecord(entry) ? entry : {};
      return {
        id: String(fields.id ?? ""),
        plugin: fields.plugin ? String(fields.plugin) : undefined,
        name: fields.name ? String(fields.name) : undefined,
      };
    }),
    plugins: plugins.map((entry) => {
      const fields = isRecord(entry) ? entry : {};
      const install = isRecord(fields.install) ? fields.install : null;
      return {
        id: String(fields.id ?? ""),
        kind: String(fields.kind ?? "asr"),
        name: String(fields.name ?? fields.id ?? ""),
        status: fields.status ? String(fields.status) : undefined,
        command: Array.isArray(fields.command) ? fields.command.map((value) => String(value)) : undefined,
        env: isRecord(fields.env)
          ? Object.fromEntries(Object.entries(fields.env).map(([key, value]) => [key, String(value)]))
          : undefined,
        install: install
          ? {
              kind: String(install.kind ?? ""),
              id: install.id ? String(install.id) : undefined,
              package: install.package ? String(install.package) : undefined,
            }
          : undefined,
        notes: fields.notes ? String(fields.notes) : undefined,
      };
    }),
  };
}

export function isPluginInstalled(id: string, home = getVoxHome()): boolean {
  return existsSync(join(pluginDirectory(id, home), "provider.json"));
}

export function installCatalogPlugin(plugin: CatalogPlugin, models: string[], home = getVoxHome()): string {
  const directory = pluginDirectory(plugin.id, home);
  mkdirSync(directory, { recursive: true });

  let command: string[];
  const installKind = plugin.install?.kind ?? (plugin.command ? "command" : "");
  if (installKind === "bundle") {
    const bundleId = plugin.install?.id ?? plugin.id;
    const source = bundledPluginPath(bundleId);
    if (!source) {
      throw new Error(`Bundled plugin '${bundleId}' is not shipped with this CLI.`);
    }
    const destination = join(directory, "provider.mjs");
    copyFileSync(source, destination);
    command = [process.execPath, destination];
  } else if (installKind === "npm") {
    const npmPackage = plugin.install?.package;
    if (!npmPackage) {
      throw new Error(`Plugin '${plugin.id}' is missing install.package.`);
    }
    command = ["npx", "-y", npmPackage];
  } else if (plugin.command && plugin.command.length > 0) {
    command = plugin.command;
  } else {
    throw new Error(`Plugin '${plugin.id}' has no install method.`);
  }

  validatePluginCommand(command);
  const provider = {
    id: plugin.id,
    kind: plugin.kind || "asr",
    command,
    models,
    env: plugin.env,
  };
  writeFileSync(join(directory, "provider.json"), `${JSON.stringify(provider, null, 2)}\n`);
  return directory;
}

export function removeInstalledPlugin(id: string, home = getVoxHome()): void {
  rmSync(pluginDirectory(id, home), { recursive: true, force: true });
}

export async function handlePlugins(subcommand: string | undefined, rest: string[]): Promise<void> {
  switch (subcommand) {
    case "list":
    case undefined: {
      const catalog = await loadCatalogDocument();
      if (catalog.plugins.length === 0) {
        console.log("No plugins in the model catalog.");
        return;
      }
      for (const plugin of catalog.plugins) {
        const models = catalog.models.filter((model) => model.plugin === plugin.id).map((model) => model.id);
        const state = isPluginInstalled(plugin.id) ? "installed" : "available";
        console.log(`${plugin.id} ${plugin.kind} ${state} ${plugin.install?.kind ?? "command"}`);
        if (models.length > 0) {
          console.log(`  models: ${models.join(", ")}`);
        }
        if (plugin.notes) {
          console.log(`  ${plugin.notes}`);
        }
      }
      return;
    }
    case "install": {
      const id = rest[0];
      if (!id) {
        throw new Error("Usage: vox plugins install <id>");
      }
      const catalog = await loadCatalogDocument();
      const plugin = catalog.plugins.find((entry) => entry.id === id);
      if (!plugin) {
        throw new Error(`Unknown catalog plugin: ${id}`);
      }
      const models = catalog.models.filter((model) => model.plugin === plugin.id).map((model) => model.id);
      const directory = installCatalogPlugin(plugin, models);
      console.log(`Installed plugin ${plugin.id} at ${directory}`);
      console.log("Restart voxd to load it.");
      return;
    }
    case "remove": {
      const id = rest[0];
      if (!id) {
        throw new Error("Usage: vox plugins remove <id>");
      }
      removeInstalledPlugin(id);
      console.log(`Removed plugin ${id}`);
      console.log("Restart voxd to drop it.");
      return;
    }
    default:
      throw new Error(`Unknown plugins command: ${subcommand}`);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
