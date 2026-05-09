export const VOXD_BRIDGE_PORT = {
  id: "companion-http",
  envVar: "VOX_BRIDGE_PORT",
  defaultPort: 43115,
  transport: "http",
  description: "Companion HTTP bridge port",
} as const;

export const DEFAULT_PORT = VOXD_BRIDGE_PORT.defaultPort;
export const DEFAULT_HOST = "127.0.0.1";
export const DEFAULT_PROBE_TIMEOUT = 2000;
export const DEFAULT_POLL_INTERVAL = 500;
