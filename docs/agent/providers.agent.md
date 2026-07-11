# Provider Protocol Facts

- transport: newline-delimited JSON-RPC 2.0 over stdin/stdout
- register ASR and TTS as separate `providers.json` entries
- `command` is a string array containing executable and arguments
- common methods: `models`, `install`, `preload`
- ASR method: `transcribe` with an audio file `path`
- TTS methods: `voices`, `synthesize`
- ASR results require `metrics.inferenceMs` and `metrics.totalMs`
- TTS results require `metrics.totalMs`; prefer `synthesisMs`
- reserve stdout for protocol messages and send logs to stderr
- provider state may cache weights, but crash/restart must remain safe
- canonical implementations: `swift/Sources/VoxEngine/ExternalProvider.swift` and `ExternalTTSProvider.swift`
