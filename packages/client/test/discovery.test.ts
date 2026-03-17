import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { RuntimeDiscovery } from "../src/discovery.ts";

describe("RuntimeDiscovery", () => {
  it("reads runtime info from VOX_RUNTIME_PATH", () => {
    const dir = mkdtempSync(join(tmpdir(), "vox-discovery-"));
    const runtimePath = join(dir, "runtime.json");
    process.env.VOX_RUNTIME_PATH = runtimePath;
    writeFileSync(runtimePath, JSON.stringify({
      version: "0.1.0",
      serviceName: "Vox",
      port: 43123,
      pid: 42,
      startedAt: new Date().toISOString(),
    }));

    const discovery = new RuntimeDiscovery();
    expect(discovery.read()?.port).toBe(43123);

    delete process.env.VOX_RUNTIME_PATH;
    rmSync(dir, { recursive: true, force: true });
  });
});
