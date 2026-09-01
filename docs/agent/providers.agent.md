# Provider Protocol Facts

- transport: newline-delimited JSON-RPC 2.0 over stdin/stdout
- register ASR and TTS as separate `providers.json` entries
- `command` is a string array containing executable and arguments
- common methods: `models`, `install`, `preload`
- ASR method: `transcribe` with an audio file `path`
- TTS methods: `voices`, `synthesize`
- ASR results require `metrics.inferenceMs` and `metrics.totalMs`
- TTS results require `metrics.totalMs`; prefer `synthesisMs`
- builtin TTS ids: `avspeech`, `openai-tts`, `elevenlabs`, `minimax`, `nvidia`, `groq`, `gemini`
- NVIDIA Magpie: model `magpie-tts-multilingual`, `NV_API_KEY`/`NVIDIA_API_KEY`, LINEAR_PCM 44.1 kHz, dynamic `list_voices`
- Groq Orpheus: WAV `response_format`, 200-character limit, `GROQ_API_KEY`
- Gemini TTS: Generate Content AUDIO, wrap `audio/L16` as WAV, `GEMINI_API_KEY`/`GOOGLE_API_KEY`
- remote TTS credentials: per-request `credentials`, then provider `env`, then process environment
- default TTS model remains `gpt-4o-mini-tts` when OpenAI is configured
- reserve stdout for protocol messages and send logs to stderr
- provider state may cache weights, but crash/restart must remain safe
- canonical implementations: `swift/Sources/HudsonSpeechEngine/` builtin TTS providers plus `ExternalTTSProvider.swift`
