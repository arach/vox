# Apple Embed Facts

## Use embed mode when

- target: macOS app or iOS app
- caller: app process
- requirement: voice in and voice out inside the app

## Use companion mode when

- target: web app or browser extension
- caller: Bun/Node tool outside the app process
- requirement: shared local voice service across processes

## Do not do this

- do not start `voxd` inside the Apple app just to call Vox APIs
- do not use `@voxd/sdk` or `@voxd/client` from app code
- do not hide warm-up as an implicit side effect

## Add package dependency

- preferred local dev dependency: `.package(path: "../vox/swift")`
- required products for app embed: `VoxCore`, `VoxEngine`
- avoid `VoxService` and `VoxBridge` unless intentionally embedding companion/runtime behavior

## Default embed engines

- ASR default: `EngineManager()` -> `ParakeetProvider()`
- TTS default: `TTSEngineManager()` -> `AVSpeechSynthesizerProvider()`
- default ASR model id: `parakeet:v3`
- default TTS model id: `TTSDefaults.modelId` = `avspeech:system`
- default TTS format: `TTSDefaults.format` = `wav`

## Public types to use

- ASR input: `URL`
- ASR output: `TranscriptionOutput`
- TTS request: `SynthesisRequest`
- TTS output: `SynthesisOutput`
- voices: `TTSVoiceInfo`
- telemetry: `PerformanceRecorder`, `PerformanceSample`

## Warm-up

- call `asr.preload(modelId:progress:)`
- call `tts.preload(modelId:voiceId:progress:)`
- do not rely on `WarmupCoordinator`; it is not public in the embed surface

## Telemetry parity

- embed mode must record telemetry manually if parity is required
- preserve fields: `clientId`, `route`, `modelId`, `voiceId`
- preserve route names: `transcribe.file`, `synthesize.generate`
- performance log path comes from `RuntimePaths.performanceLogURL()`

## App owns these concerns

- microphone permission
- audio capture
- temp-file creation for ASR input
- playback of `SynthesisOutput.audioData`
- interruption handling
- product state and UI

## OpenAI TTS rule

- start with AVSpeech for default Apple embed mode
- if remote TTS is needed, use `TTSProviderRegistry(config:)`
- pass `OPENAI_API_KEY` via `ProviderEntry.env` or app config
- do not rely on process environment inside iOS app code

## Known gaps

- no public one-object Apple SDK facade yet
- no public embed live-session coordinator yet
- no raw-buffer ASR API yet
- no automatic telemetry recording in embed mode

## Linea default recipe

- client id: `linea-ios` or `linea-macos`
- ASR engine: `EngineManager()`
- TTS engine: `TTSEngineManager()`
- TTS default: `avspeech:system`
- use Vox Companion only for web or cross-process workflows
