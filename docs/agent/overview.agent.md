# Vox Facts

- platforms: `macOS 14+` / `iOS 17+` for Swift transcription embedding; `macOS 14+` for Minivox; `macOS 26+` for the Hudson menu app
- deployment modes:
  - embed mode: Swift packages inside the app process
  - companion mode: `voxd` for web, browser, and shared-process clients
- default ASR embed engine: `EngineManager()` -> `ParakeetProvider()`
- default TTS embed engine: `TTSEngineManager()` -> `TTSProviderRegistry`
- companion service: `VoxRuntimeService`
- CLI: `@voxd/cli` (Bun)
- companion SDK: `@voxd/sdk` (TypeScript, WebSocket JSON-RPC to `voxd`)
- browser SDK: `@voxd/client` (HTTP bridge to Vox Companion)
- full companion app: `apps/vox/`
- Minivox dictation app: `apps/minivox/`
- Minivox install: `npx -y @voxd/cli@latest install mini` or `brew install --cask arach/vox/minivox`
- model focus: `parakeet:v3` for ASR, `gpt-4o-mini-tts` for default TTS
- warmup: explicit API surface
- telemetry dimensions: `clientId`, `route`, `modelId`, `voiceId`
- configurable: `VOX_PORT`, `VOX_BRIDGE_PORT`, `VOX_HOST`, `VOX_HOME`
