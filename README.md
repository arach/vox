# Vox

Vox is a macOS-first local transcription runtime built as a Bun + SwiftPM monorepo.

## Layout

- `swift/` contains `VoxCore`, `VoxEngine`, `VoxService`, and the `voxd` daemon.
- `packages/client` contains the TypeScript SDK for talking to the daemon over local WebSocket JSON-RPC.
- `packages/cli` contains the `vox` CLI.

## Commands

```bash
bun install
bun run build
bun run test
bun run test:e2e
```

### CLI examples

```bash
vox daemon start
vox doctor
vox models list
vox models install
vox transcribe file /path/to/audio.wav
vox transcribe live
```

## Runtime

The daemon writes runtime discovery metadata to `~/.vox/runtime.json`.

`bun run test:e2e` is an opt-in macOS integration suite. It boots `voxd`, preloads the model, synthesizes short speech samples with `say`, and verifies real `transcribe file` output against keyword checks.
