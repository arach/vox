# transcribe-tui

A terminal transcription dashboard built on the Vox SDK and [Ink](https://github.com/vadimdemedes/ink).

## Usage

```bash
# make sure the daemon is running
vox daemon start

# batch mode — pass files as arguments
bun run index.tsx recording.wav meeting.m4a

# interactive mode — type file paths in the input bar
bun run index.tsx
```

## Layout

```
┌──────────────────────────────────────────────────┐
│ ▲ Vox transcribe-tui   ● voxd  ● model warm     │
├──────────────────────────────────┬────────────────┤
│ Transcript                      │ Files          │
│                                 │ ✓ meeting.wav  │
│ "The quarterly results show..." │ ⟳ call.m4a     │
│                                 │                │
├──────────────────────────────────┤                │
│ Stage Timings                   │                │
│ file check   ██░░░░░  2.1ms     │                │
│ model load   █░░░░░░  0.3ms     │                │
│ inference    ████████ 142.0ms   │                │
│ total        █████████ 151.2ms  │                │
├──────────────────────────────────┴────────────────┤
│ ▸ /path/to/file.wav   │ enter: transcribe · q: quit │
└──────────────────────────────────────────────────┘
```

## What it does

1. Connects to `voxd` and warms the model
2. Split-pane dashboard: transcript on the left, file list on the right
3. Inline metric bars for every transcription stage
4. Interactive input bar — type paths, hit enter, see results
