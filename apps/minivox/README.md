# Minivox

A tiny macOS menu-bar app for fast, local dictation.

Minivox deliberately does one thing:

1. record a short voice note;
2. transcribe it locally with Parakeet through `VoxEngine`;
3. copy the finished text to the clipboard.

There is no `voxd`, browser bridge, reply engine, or text-to-speech step. The app keeps warm-up visible and shows transcription timing without turning dictation into a dashboard.

## Run

From the repository root:

```bash
swift run --package-path apps/minivox Minivox
```

The first dictation may download and load Parakeet. Minivox asks for microphone access when you record for the first time. Use the visible **Warm up Parakeet** control when you want the model ready before you start speaking.

## Package

Create a signed local app bundle and disk image from the repository root:

```bash
bun run minivox:bundle
```

The package is written to `dist/minivox/Minivox.dmg`. Local builds are ad hoc signed and stay out of the website download directory by default. Set `MINIVOX_SIGN_IDENTITY` and `MINIVOX_NOTARY_PROFILE` to create a Developer ID-signed and notarized release.

## Core integration

```swift
let asr = EngineManager()

let transcript = try await asr.transcribe(
    url: recordingURL,
    modelId: "parakeet:v3"
)

NSPasteboard.general.clearContents()
NSPasteboard.general.setString(transcript.text, forType: .string)
```

Minivox is the small, single-purpose Vox app: it owns microphone capture and runs `VoxEngine` in process.
