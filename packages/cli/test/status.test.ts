import { existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { minivoxReleaseDownloadURL, parseMinivoxInstallOptions } from "../src/index.ts";

describe("runtime fixture", () => {
  it("can create a temporary runtime file for CLI tests", () => {
    const dir = mkdtempSync(join(tmpdir(), "vox-cli-"));
    const file = join(dir, "runtime.json");
    writeFileSync(file, JSON.stringify({ port: 42137, pid: 1, serviceName: "Vox", version: "0.1.0", startedAt: new Date().toISOString() }));
    expect(existsSync(file)).toBe(true);
    rmSync(dir, { recursive: true, force: true });
  });
});

describe("Minivox installer", () => {
  it("downloads the release matching the CLI version", () => {
    expect(minivoxReleaseDownloadURL("0.4.0")).toBe(
      "https://github.com/arach/vox/releases/download/v0.4.0/Minivox.dmg",
    );
  });

  it("accepts the documented install options", () => {
    expect(parseMinivoxInstallOptions(["--user", "--no-launch"])).toEqual({
      user: true,
      launch: false,
    });
  });

  it("rejects unknown install options", () => {
    expect(() => parseMinivoxInstallOptions(["--system"])).toThrow(
      "Unknown Minivox install option: --system",
    );
  });
});
