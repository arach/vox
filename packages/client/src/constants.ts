import { homedir } from "os";
import { join } from "path";

export const DEFAULT_PORT = 42137;
export const CONNECT_TIMEOUT_MS = 5_000;
export const CALL_TIMEOUT_MS = 30_000;
export const STREAM_TIMEOUT_MS = 300_000;

export function getVoxHome(): string {
  return process.env.VOX_HOME ?? join(homedir(), ".vox");
}

export function getRuntimeFilePath(): string {
  return process.env.VOX_RUNTIME_PATH ?? join(getVoxHome(), "runtime.json");
}
