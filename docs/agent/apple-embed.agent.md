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
- optional product for Apple playback: `VoxAppleSpeech` / `AppleSpeechOutputController`
- avoid `VoxService` and `VoxBridge` unless intentionally embedding companion/runtime behavior

## Default embed engines

- ASR default: `EngineManager()` -> `ParakeetProvider()`
- TTS generation default: `TTSEngineManager()` -> `TTSProviderRegistry` with OpenAI TTS plus AVSpeech fallback
- TTS playback is not on `TTSProvider`; optional Apple playback is `AppleSpeechOutputController`
- default ASR model id: `parakeet:v3`
- default TTS model id: `TTSDefaults.modelId` = `gpt-4o-mini-tts`
- local TTS model id: `TTSDefaults.localModelId` = `avspeech:system`
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
- product-level spoken-output policy (dedupe, markdown flattening, fallback copy, preferences, queue priority)
- playback of `SynthesisOutput.audioData`, or an opt-in `AppleSpeechOutputController` per audible surface
- interruption handling
- product state and UI

## OpenAI TTS rule

- OpenAI TTS is the default API-backed model when an API key is configured
- use `TTSDefaults.localModelId` when a caller intentionally wants AVSpeech
- pass `OPENAI_API_KEY` via `ProviderEntry.env` or app config
- do not rely on process environment inside iOS app code

## Optional Apple playback

- `VoxAppleSpeech` is optional and per audible surface, not a singleton
- `avspeech:system` uses live `AVSpeechSynthesizer.speak()`, never `write()`-then-play
- generated-audio models play `SynthesisOutput.audioData` through an injectable player sink
- audio-session configuration is injectable and off by default
- new requests replace pending generation/playback
- stop/cancel are idempotent and must cancel Task, player, and synthesizer during the enqueue window
- events report resolving/generating, starting, playing, finished, cancelled, failed
- synthesis identity reports requested vs actual model/voice, not a guessed provider id
- synthesis identity is separate from the physical audio-output route
- do not put reply dedupe, markdown flattening, fallback copy, preference storage, queue priority, or telemetry double-recording in this controller

## Known gaps

- no public one-object Apple SDK facade yet; `VoxAppleSpeech` is playback, not that facade
- no public embed live-session coordinator yet
- no raw-buffer ASR API yet
- no automatic telemetry recording in embed mode
- `VoxAppleSpeech` does not own browser playback or app product policy

## Linea default recipe

- client id: `linea-ios` or `linea-macos`
- ASR engine: `EngineManager()`
- TTS engine: `TTSEngineManager()`
- TTS default: `gpt-4o-mini-tts`
- TTS local fallback: `avspeech:system`
- use Vox Companion only for web or cross-process workflows
