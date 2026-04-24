# Vox Facts

- platform: macOS-first
- runtime: Swift daemon (`voxd`)
- CLI: `@voxd/cli` (Bun)
- SDK: `@voxd/sdk` (TypeScript, WebSocket JSON-RPC to daemon)
- browser SDK: `@voxd/client` (HTTP bridge to companion)
- model focus: Parakeet
- warmup: explicit API surface
- telemetry dimensions: `clientId`, `route`, `modelId`
- configurable: `VOX_PORT`, `VOX_BRIDGE_PORT`, `VOX_HOST` env vars
