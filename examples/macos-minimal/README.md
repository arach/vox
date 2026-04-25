# macos-minimal

A tiny macOS voice loop app that embeds Vox directly in process.

It keeps the integration surface intentionally small:

- microphone capture in the app itself
- Parakeet ASR through `VoxEngine`
- Apple Intelligence replies through `FoundationModels`
- Qwen3 0.6B MLX fallback through `uv` + `mlx-lm`
- Kokoro TTS through `VoxEngine`
- no `voxd`
- no bridge setup

## Run

```bash
cd examples/macos-minimal
swift run VoxMinimalExample
```

The first spoken turn uses `uv` to create the MLX provider environment and download what Kokoro needs. The first transcription may also download and load the local ASR model. If Apple Intelligence is unavailable, the first reply turn can also download the official `Qwen/Qwen3-0.6B-MLX-4bit` checkpoint for the local fallback.

The app will ask for microphone access on the first record attempt. If Apple Intelligence is enabled, the app uses it first. If not, it falls back to the local Qwen model automatically.

## Core Integration

```swift
let tts = TTSEngineManager(provider: TTSProviderRegistry(config: ProvidersConfig(providers: [
    ProviderEntry(
        id: "mlx-audio",
        kind: .tts,
        builtin: true,
        models: ["mlx-community/Kokoro-82M-bf16"],
        env: [
            "VOX_MLX_AUDIO_USE_UV": "1",
            "VOX_MLX_AUDIO_TTS_MODELS": "mlx-community/Kokoro-82M-bf16",
        ]
    )
])))

let asr = EngineManager()

let transcript = try await asr.transcribe(
    url: fileURL,
    modelId: "parakeet:v3"
)

let reply = try await ResponseEngineService.generateReply(for: transcript.text)

let speech = try await tts.synthesize(SynthesisRequest(
    text: reply.text,
    modelId: "mlx-community/Kokoro-82M-bf16",
    voiceId: "af_heart"
))
```
