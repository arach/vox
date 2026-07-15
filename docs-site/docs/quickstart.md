# Quickstart

## Prerequisites

- macOS 14+ or iOS 17+ for direct Swift transcription embedding; macOS 14+ for Minivox; macOS 26+ for the Vox menu app
- Node 22+
- Vox Companion installed from the DMG, or `voxd` available at `~/.vox/bin/voxd`
- Swift 6.2+ only if you plan to build Vox from a repo checkout

## Install and verify

```bash
npm install -g @voxd/cli
vox install
vox doctor       # expect ready: true
```

`vox install` registers the LaunchAgent for an existing `voxd` binary. The simplest path is to install `Vox.dmg` first, then run the CLI.

If you are running from a repo checkout instead of a global install, replace `vox` with `node packages/cli/dist/index.js` after `bun run build`.

If you are building a browser client, pair the local companion with `@voxd/client` and the [Web Integration Guide](./web-integration.md).

## Speech to text

```bash
vox warmup start parakeet:v3
vox transcribe file --model parakeet:v3 /path/to/audio.wav --metrics --timestamps
vox transcribe bench --model parakeet:v3 /path/to/audio.wav 5
```

Warm-up skips cold-start cost. `transcribe file` prints transcript text, stage timings, and optional word-level timestamps. `bench` gives you warm-path variance for the same clip.

## Text to speech

```bash
vox voices --model avspeech:system
vox speak --model avspeech:system --metrics "Hello from Vox"
vox speak bench --model avspeech:system "Hello from Vox" 5
```

`voices` shows available presets for the selected model. `speak` synthesizes audio immediately and prints synthesis metrics when `--metrics` is set. `speak bench` repeats the same request so you can compare warm-path TTS behavior.

## External providers

For non-Parakeet ASR or non-system TTS, add entries to `~/.vox/providers.json` and then pass the returned model ID with `--model`.

The [Provider Protocol](./providers.md) includes built-in `mlx-audio` examples for both STT and TTS.

## Measure and inspect

```bash
vox perf dashboard --client vox-cli
vox logs daemon --tail 80
vox transcribe status
```

`perf dashboard` shows latency samples by client, route, and model. Use `logs daemon` and `transcribe status` when a live session gets stuck or the mic is busy.

## Common failure cases

- Missing ASR model: `vox models list` then `vox models install`
- TTS provider or voice issue: `vox voices --model <id>` then retry `vox speak --model <id> ...`
- External TTS model install/setup: follow the provider's own setup flow, such as the `mlx-audio` environment in `~/.vox/providers.json`
- Wrong or missing voice: `vox voices --model <id>`
- External provider missing dependencies: verify `~/.vox/providers.json` and any referenced interpreter or API key
- Cold runtime: `vox warmup start` or `vox warmup schedule`
- No performance data: run a `transcribe` or `speak` command first so the runtime emits samples
- Stuck live session: `vox transcribe status` then `vox transcribe cancel`
- Need daemon logs: `vox logs daemon --tail 120`

## Next steps

If you are integrating Vox into a macOS or iOS app, read the [Swift Embed Guide](./apple-embed.md).

If you are wiring external STT or TTS engines into Vox Companion, read the [Provider Protocol](./providers.md).

Try [Minivox](https://github.com/arach/vox/tree/main/apps/minivox), the small menu-bar dictation app built directly on Vox. The [transcribe TUI](https://github.com/arach/vox/tree/main/examples/transcribe-tui) remains the companion-connected terminal sample.
