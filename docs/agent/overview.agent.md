# Vox Facts

- platforms: `macOS 26+`, `iOS 26+`
- deployment modes:
  - embed mode: Swift packages inside the app process
  - companion mode: `voxd` for web, browser, and shared-process clients
- default ASR embed engine: `EngineManager()` -> `ParakeetProvider()`
- default TTS embed engine: `TTSEngineManager()` -> `AVSpeechSynthesizerProvider()`
- companion service: `VoxRuntimeService`
- CLI: `@voxd/cli` (Bun)
- companion SDK: `@voxd/sdk` (TypeScript, WebSocket JSON-RPC to `voxd`)
- browser SDK: `@voxd/client` (HTTP bridge to Vox Companion)
- model focus: `parakeet:v3` for ASR, `avspeech:system` for default TTS
- warmup: explicit API surface
- telemetry dimensions: `clientId`, `route`, `modelId`, `voiceId`
- configurable: `VOX_PORT`, `VOX_BRIDGE_PORT`, `VOX_HOST`, `VOX_HOME`
