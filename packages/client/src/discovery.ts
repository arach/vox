import { existsSync, readFileSync } from "fs";
import { DEFAULT_PORT, getRuntimeFilePath } from "./constants.ts";
import { ServiceUnavailableError } from "./errors.ts";
import type { RuntimeInfo } from "./types.ts";

export class RuntimeDiscovery {
  read(): RuntimeInfo | null {
    const runtimePath = getRuntimeFilePath();
    if (!existsSync(runtimePath)) {
      return null;
    }

    try {
      const raw = readFileSync(runtimePath, "utf8");
      const parsed = JSON.parse(raw) as RuntimeInfo;
      if (!parsed.port || !parsed.pid || !parsed.serviceName) {
        return null;
      }
      return parsed;
    } catch {
      return null;
    }
  }

  resolvePort(overridePort?: number): number {
    if (overridePort) {
      return overridePort;
    }

    const runtime = this.read();
    if (runtime?.port) {
      return runtime.port;
    }

    return DEFAULT_PORT;
  }

  requireRuntime(): RuntimeInfo {
    const runtime = this.read();
    if (!runtime) {
      throw new ServiceUnavailableError(`No runtime info found at ${getRuntimeFilePath()}`);
    }
    return runtime;
  }
}
