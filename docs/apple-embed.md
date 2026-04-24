---
title: Apple Embed Guide
description: Agent-oriented instructions for integrating Vox directly into macOS and iOS apps such as Linea.
---

# Apple Embed Guide

Use this guide when modifying a macOS or iOS app repo that should call Vox directly in process. This is the right path for apps such as Linea and other Apple-native clients.

## Decision rule

- If the caller is app code running inside a macOS or iOS process, use embed mode.
- If the caller is a web app, browser extension, or Bun/Node tool outside the app process, use Vox Companion (`voxd`).
- Do not start `voxd` inside an Apple app just to get access to Vox APIs. That is the wrong mode.

## What embed mode is today

The current public embed surface is low-level but usable:

- ASR: `EngineManager`
- TTS: `TTSEngineManager`, `SynthesisRequest`
- outputs: `TranscriptionOutput`, `SynthesisOutput`, `TTSVoiceInfo`
- telemetry: `PerformanceRecorder`, `PerformanceSample`
- provider composition: `ProviderRegistry`, `TTSProviderRegistry`, `ProvidersConfig`, `ProviderEntry`

There is not yet a polished one-object Apple SDK facade. Agents should usually create a thin app-local wrapper such as `VoiceService` or `LineaVoiceStack` and keep raw Vox types behind that boundary.

## Package setup

For a sibling repo during local development, prefer a local SwiftPM dependency:

```swift
.package(path: "../vox/swift")
```

Add these product dependencies to the app target:

- `VoxCore`
- `VoxEngine`

Only add `VoxService` or `VoxBridge` if the app intentionally embeds companion/runtime behavior. That is not the default Apple app path.

## Minimal local-first service

```swift
import Foundation
import VoxCore
import VoxEngine

actor LineaVoiceStack {
    private let clientId: String
    private let asr: EngineManager
    private let tts: TTSEngineManager
    private let performance = PerformanceRecorder()

    init(clientId: String = "linea-ios") {
        self.clientId = clientId
        self.asr = EngineManager()      // Parakeet
        self.tts = TTSEngineManager()   // AVSpeechSynthesizer
    }

    func warmup() async throws {
        _ = try await asr.preload(modelId: "parakeet:v3") { _ in }
        _ = try await tts.preload(modelId: TTSDefaults.modelId, voiceId: nil) { _ in }
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionOutput {
        let output = try await asr.transcribe(url: fileURL, modelId: "parakeet:v3")

        await performance.record(
            PerformanceSample(
                clientId: clientId,
                route: "transcribe.file",
                modelId: output.modelId,
                outcome: "ok",
                textLength: output.text.count,
                metrics: output.metrics.performanceMetrics
            )
        )

        return output
    }

    func synthesize(text: String, voiceId: String? = nil) async throws -> SynthesisOutput {
        let output = try await tts.synthesize(
            SynthesisRequest(
                text: text,
                modelId: TTSDefaults.modelId,
                voiceId: voiceId
            )
        )

        await performance.record(
            PerformanceSample(
                clientId: clientId,
                route: "synthesize.generate",
                modelId: output.modelId,
                voiceId: output.voiceId,
                outcome: "ok",
                textLength: text.count,
                metrics: output.metrics.performanceMetrics
            )
        )

        return output
    }
}
```

## App responsibilities

In embed mode, the app still owns:

- microphone permission
- audio capture
- temp-file creation for ASR input
- audio playback for synthesized WAV data
- interruption handling
- product-level state and UX

Today the ASR entrypoint takes a `URL`, not an in-memory audio buffer. Agents should capture audio, write it to a temporary file, then call `transcribe(url:modelId:)`.

TTS returns WAV bytes in `SynthesisOutput.audioData`. Agents should hand that data to the app playback layer, such as `AVAudioPlayer` or `AVAudioEngine`.

## Warm-up

Warm-up must remain explicit.

- ASR warm-up: `EngineManager.preload(modelId:progress:)`
- TTS warm-up: `TTSEngineManager.preload(modelId:voiceId:progress:)`

Do not hide warm-up behind app launch side effects unless the product intentionally wants that behavior. Prefer warming on intent or at a predictable app state transition.

## Telemetry

Companion mode records telemetry automatically. Embed mode does not.

If the app wants parity with Vox Companion telemetry, record samples yourself with `PerformanceRecorder` and preserve these dimensions:

- `clientId`
- `route`
- `modelId`
- `voiceId` for synthesis

Use the same route names Vox Companion uses:

- `transcribe.file`
- `synthesize.generate`

`RuntimePaths.performanceLogURL()` resolves to:

- macOS: `~/.vox/performance.jsonl`
- iOS: `Application Support/Vox/performance.jsonl`

## OpenAI TTS in embed mode

The zero-dependency default is:

- ASR: `EngineManager()` -> `ParakeetProvider()`
- TTS: `TTSEngineManager()` -> `AVSpeechSynthesizerProvider()`

If the app needs remote TTS, create a registry explicitly. Prefer passing secrets in code or app configuration rather than relying on process environment inside an iOS app.

```swift
let ttsConfig = ProvidersConfig(providers: [
    ProviderEntry(
        id: "avspeech",
        kind: .tts,
        builtin: true,
        models: [AVSpeechSynthesizerProvider.modelID]
    ),
    ProviderEntry(
        id: "openai-tts",
        kind: .tts,
        builtin: true,
        models: OpenAITTSProvider.supportedModelIDs,
        env: ["OPENAI_API_KEY": apiKey]
    )
])

let tts = TTSEngineManager(provider: TTSProviderRegistry(config: ttsConfig))
```

## Linea default plan

For the first Linea integration, the default plan should be:

- use embed mode on iOS and macOS
- add `VoxCore` and `VoxEngine`
- wrap Vox in one app-local actor or service
- use `parakeet:v3` for ASR
- use `avspeech:system` for default TTS
- record Vox-compatible telemetry from the app
- introduce OpenAI TTS only if product requirements need remote voices
- use Vox Companion only for web surfaces or cross-process workflows

## What agents should not assume

- There is no public one-object Apple SDK facade yet.
- There is no public embed live-session coordinator yet.
- There is no public embed warm-up coordinator helper.
- Embed mode does not automatically write performance samples.
- Apple apps do not need `@voxd/sdk` or `@voxd/client`.

## First tasks in a sibling app repo

1. Add `../vox/swift` as a local package dependency.
2. Create a single `VoiceService` or `LineaVoiceStack` actor in app code.
3. Warm the ASR and TTS engines explicitly.
4. Feed ASR with file URLs, not raw buffers.
5. Feed TTS output WAV data into the app playback layer.
6. Emit `PerformanceSample` records with stable route names.
7. Keep Companion mode out of the Apple app path unless the feature is genuinely web or cross-process.
