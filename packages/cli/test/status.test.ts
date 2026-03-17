import { existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

describe("runtime fixture", () => {
  it("can create a temporary runtime file for CLI tests", () => {
    const dir = mkdtempSync(join(tmpdir(), "vox-cli-"));
    const file = join(dir, "runtime.json");
    writeFileSync(file, JSON.stringify({ port: 42137, pid: 1, serviceName: "Vox", version: "0.1.0", startedAt: new Date().toISOString() }));
    expect(existsSync(file)).toBe(true);
    rmSync(dir, { recursive: true, force: true });
  });
});
