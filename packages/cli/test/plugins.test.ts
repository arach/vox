import { mkdtempSync, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  installCatalogPlugin,
  isPluginInstalled,
  parseCatalog,
  removeInstalledPlugin,
  validatePluginCommand,
  validatePluginId,
} from "../src/plugins.ts";

describe("plugin catalog", () => {
  it("parses catalog plugins and model plugin ids", () => {
    const catalog = parseCatalog({
      version: 1,
      updatedAt: "2026-08-29",
      plugins: [
        {
          id: "mlx-vlm",
          kind: "asr",
          name: "MLX-VLM",
          install: { kind: "bundle", id: "mlx-vlm" },
        },
      ],
      models: [{ id: "gemma-4-e2b-it", plugin: "mlx-vlm", name: "Gemma 4 E2B" }],
    });

    expect(catalog.plugins[0]?.id).toBe("mlx-vlm");
    expect(catalog.plugins[0]?.install?.kind).toBe("bundle");
    expect(catalog.models[0]?.plugin).toBe("mlx-vlm");
  });

  it("rejects disallowed plugin launchers", () => {
    expect(() => validatePluginCommand(["bash", "-c", "echo hi"])).toThrow("not allowed");
    expect(() => validatePluginCommand(["node", "ok.mjs"])).not.toThrow();
  });

  it("rejects plugin ids that can escape the plugins directory", () => {
    for (const id of ["../escape", "nested/plugin", "nested\\plugin", "a..b", ".hidden", "Uppercase"]) {
      expect(() => validatePluginId(id)).toThrow("not allowed");
    }
    for (const id of ["mlx-vlm", "mlx_vlm.v2", "plugin-2"]) {
      expect(() => validatePluginId(id)).not.toThrow();
    }
  });

  it("rejects traversal ids before install or removal touches the filesystem", () => {
    const home = mkdtempSync(join(tmpdir(), "vox-plugin-traversal-"));
    try {
      expect(() =>
        installCatalogPlugin(
          {
            id: "../escape",
            kind: "asr",
            name: "Escape",
            command: ["node", "provider.mjs"],
          },
          [],
          home,
        ),
      ).toThrow("not allowed");
      expect(() => removeInstalledPlugin("../escape", home)).toThrow("not allowed");
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });

  it("installs the bundled mlx-vlm plugin into VOX_HOME", () => {
    const home = mkdtempSync(join(tmpdir(), "vox-plugins-"));
    const previous = process.env.VOX_HOME;
    process.env.VOX_HOME = home;
    try {
      const directory = installCatalogPlugin(
        {
          id: "mlx-vlm",
          kind: "asr",
          name: "MLX-VLM",
          install: { kind: "bundle", id: "mlx-vlm" },
        },
        ["gemma-4-e2b-it"],
        home,
      );
      expect(isPluginInstalled("mlx-vlm", home)).toBe(true);
      const provider = JSON.parse(readFileSync(join(directory, "provider.json"), "utf8")) as {
        id: string;
        command: string[];
        models: string[];
      };
      expect(provider.id).toBe("mlx-vlm");
      expect(provider.models).toEqual(["gemma-4-e2b-it"]);
      expect(["node", "bun"].includes(provider.command[0]?.split(/[/\\]/).pop() ?? "")).toBe(true);
      expect(provider.command[1]?.endsWith("provider.mjs")).toBe(true);
      removeInstalledPlugin("mlx-vlm", home);
      expect(isPluginInstalled("mlx-vlm", home)).toBe(false);
    } finally {
      if (previous === undefined) {
        delete process.env.VOX_HOME;
      } else {
        process.env.VOX_HOME = previous;
      }
      rmSync(home, { recursive: true, force: true });
    }
  });
});
