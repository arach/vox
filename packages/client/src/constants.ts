import { homedir } from "os";
import { join } from "path";

export const VOX_PORTS = {
  daemon: {
    id: "companion-ws",
    envVar: "VOX_PORT",
    defaultPort: 42137,
    transport: "ws",
    description: "Companion daemon WebSocket port",
    storedInRuntimeFile: true,
  },
  bridge: {
    id: "companion-http",
    envVar: "VOX_BRIDGE_PORT",
    defaultPort: 43115,
    transport: "http",
    description: "Companion HTTP bridge port",
    storedInRuntimeFile: false,
  },
} as const;

export const DEFAULT_PORT = VOX_PORTS.daemon.defaultPort;
export const DEFAULT_HOST = "127.0.0.1";
export const DEFAULT_HOST_ENV = "VOX_HOST";
export const CONNECT_TIMEOUT_MS = 5_000;
export const CALL_TIMEOUT_MS = 30_000;
export const STREAM_TIMEOUT_MS = 300_000;

export function getVoxHome(): string {
  return process.env.VOX_HOME ?? join(homedir(), ".vox");
}

export function getRuntimeFilePath(): string {
  return process.env.VOX_RUNTIME_PATH ?? join(getVoxHome(), "runtime.json");
}
