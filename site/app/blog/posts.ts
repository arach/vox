export interface BlogPost {
  slug: string;
  title: string;
  date: string;
  summary: string;
  content: string;
}

export const posts: BlogPost[] = [
  {
    slug: "why-vox",
    title: "Why I Built Vox",
    date: "2026-03-15",
    summary:
      "I kept rebuilding the same transcription plumbing for every project. Vox is what fell out of that — a runtime that handles the boring parts so you can skip to the interesting ones.",
    content: `I was building a macOS app that needed voice input. Mic permissions, audio capture, model loading, keeping things warm so the first command doesn't lag. I got it working. Then I needed the same thing in a Raycast extension. Then a browser extension. Each time I was solving the same problems — and none of them had anything to do with what I was actually trying to build.

So I pulled the runtime out into its own thing. That's Vox.

## The interesting part isn't the runtime

There's already great transcription out there. Whisper, Parakeet, Deepgram — the model layer is genuinely good. What's less fun is everything around it. Getting mic permissions right on macOS. Keeping a model loaded so you don't pay cold-start on every request. Making sure two apps don't load separate copies of the same 600MB model. Measuring where time actually goes.

These are solved problems individually, but everyone solves them again from scratch. Vox just bundles them into a daemon that stays running. A Swift service handles the audio engine and model lifecycle. A TypeScript SDK connects over local WebSocket. A Bun CLI gives you tools to measure and poke at things. It ships with Parakeet running on-device via CoreML.

## Why open source it

Honestly, I'd just use it myself either way. But it seemed like the kind of thing that might save someone else a few weekends. If you're building a voice feature on macOS — a dictation tool, an editor plugin, something with Raycast — the runtime part shouldn't be the hard part. The hard part should be whatever you're actually making.

The internals are intentionally visible. Warm-up is a public API. Stage timings come back with every transcription. Client identity flows through the telemetry so you can tell which integration is slow. I built it this way because I needed to debug my own stuff, and it turns out that's useful for anyone building on top of it.

## Where it's going

Vox ships with one model today, but the architecture supports plugging in others. There's a provider protocol — any executable that reads audio and writes text over stdin/stdout can be a transcription engine. So if Parakeet isn't right for your use case, you can bring Whisper or whatever else without touching the runtime.

I don't have grand plans for this. If people find it useful, great. If not, I'll keep using it for my own projects. The code is open source and the docs are up.

## Get started

\`\`\`bash
git clone https://github.com/arach/vox.git && cd vox
bun install && bun run build
vox daemon start && vox doctor
\`\`\`

Four commands, working transcription. The docs cover the rest.`,
  },
  {
    slug: "provider-protocol",
    title: "The Provider Protocol: Bring Your Own Transcription Engine",
    date: "2026-03-17",
    summary:
      "Vox is a runtime, not a model. We're introducing the Provider Protocol so any executable that speaks JSON-RPC over stdin/stdout can be a transcription engine.",
    content: `Vox handles the hard, boring parts of transcription on macOS: mic permissions, audio capture, session lifecycle, warm-up scheduling, multi-client coordination, telemetry. It ships today with Parakeet running on-device via CoreML. Parakeet is fast, private, and good enough for most use cases.

But locking users to one model is the wrong move.

Some teams need Whisper for accuracy on medical terminology. Some want Deepgram for streaming over a network. Some are training their own models and need a way to plug them in without forking the runtime. The right abstraction isn't "pick the best model" — it's "bring whatever model fits your problem."

So we're introducing the Provider Protocol.

## What a provider is

A provider is any executable that speaks JSON-RPC over stdin/stdout. That's it. No SDK to import, no WebSocket server to run, no session management to implement. Vox spawns the process, sends it audio, and reads back text.

The contract is deliberately thin. Vox hands you clean 16kHz PCM audio. You hand back text and stage timings. A provider doesn't know about WebSocket connections, doesn't manage sessions, doesn't deal with mic permissions. It's a pure transformation: audio in, text and metrics out.

If you can write a script that reads from stdin and writes to stdout, you can build a provider.

## The protocol surface

The protocol defines four methods:

\`\`\`typescript
// What models does this provider offer?
interface ModelsRequest {
  method: "models";
}
interface ModelsResponse {
  models: Array<{
    id: string;          // e.g. "whisper-large-v3"
    name: string;        // human-readable
    sizeBytes?: number;  // so Vox can show install progress
  }>;
}

// Download or prepare a model for use
interface InstallRequest {
  method: "install";
  params: { modelId: string };
}

// Load the model into memory ahead of speech
interface PreloadRequest {
  method: "preload";
  params: { modelId: string };
}

// The actual work
interface TranscribeRequest {
  method: "transcribe";
  params: {
    modelId: string;
    audio: string;       // base64-encoded 16kHz PCM
    sampleRate: number;
  };
}
interface TranscribeResponse {
  text: string;
  segments?: Array<{
    text: string;
    startMs: number;
    endMs: number;
  }>;
  timings: {
    loadMs?: number;
    inferenceMs: number;
    totalMs: number;
  };
}
\`\`\`

\`models\` lets Vox discover what a provider offers. \`install\` handles any one-time setup — downloading weights, compiling a model, pulling a container image. \`preload\` warms the model into memory so the first transcription doesn't pay a cold-start tax. \`transcribe\` does the work.

Notice what's missing: no authentication, no streaming protocol, no configuration negotiation. Providers don't need to know how Vox routes requests or manages clients. They just respond to these four methods.

## Registration

Users register providers in \`~/.vox/providers.json\`:

\`\`\`json
{
  "providers": [
    {
      "id": "whisper-cpp",
      "command": "/usr/local/bin/vox-whisper",
      "args": ["--threads", "4"],
      "env": { "WHISPER_MODEL_DIR": "~/.vox/models" }
    },
    {
      "id": "deepgram",
      "command": "bun",
      "args": ["run", "~/.vox/providers/deepgram/index.ts"],
      "env": { "DEEPGRAM_API_KEY": "\${DEEPGRAM_API_KEY}" }
    }
  ]
}
\`\`\`

Point to a binary, a script, a container entrypoint. Vox spawns the process, speaks the protocol, and routes requests by model ID. If a client requests \`whisper-large-v3\` and that model belongs to the \`whisper-cpp\` provider, Vox sends the work there. If no model ID is specified, Vox falls back to the default provider (Parakeet, unless you've changed it).

## What this means in practice

You can write a provider in any language. A Python script wrapping whisper.cpp. A Rust binary calling Deepgram's API. A Bun script that sends audio to a cloud endpoint. Whatever fits your use case.

Here's a minimal provider in TypeScript that echoes back a fixed response — useful as a starting point:

\`\`\`typescript
import { createInterface } from "readline";

const rl = createInterface({ input: process.stdin });

rl.on("line", (line) => {
  const req = JSON.parse(line);

  if (req.method === "models") {
    respond(req.id, {
      models: [{ id: "echo-v1", name: "Echo Provider" }],
    });
  }

  if (req.method === "transcribe") {
    const start = performance.now();
    // Your inference logic here
    const elapsed = performance.now() - start;

    respond(req.id, {
      text: "transcribed text goes here",
      timings: { inferenceMs: elapsed, totalMs: elapsed },
    });
  }
});

function respond(id: string, result: unknown) {
  process.stdout.write(
    JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n"
  );
}
\`\`\`

That's a complete provider. It handles \`models\` and \`transcribe\`, ignores methods it doesn't care about, and writes JSON-RPC responses to stdout. Replace the echo logic with a real model call and you have a working transcription engine.

## Telemetry across providers

One thing we were careful about: Vox's telemetry still works across all providers. Every performance sample carries \`modelId\` as a dimension. This means you can run Parakeet and Whisper side by side, compare p50 latency, and make data-driven decisions about which model to use for which workload.

The \`timings\` object in the transcribe response gives Vox the stage breakdown — load time, inference time, total time. Vox adds its own measurements (audio capture duration, WebSocket overhead, queue wait) and writes the complete picture to \`performance.jsonl\`. Same format, same dashboard, regardless of which provider did the work.

## Performance cost

The obvious question: what does a process boundary cost you?

Not much. The IPC overhead — JSON serialization, pipe write, pipe read, deserialization — adds roughly 0.1 to 0.2ms per transcription round-trip. A typical Parakeet inference takes 130-200ms. So the protocol overhead is less than 0.1% of the total. You can't measure it.

Process startup is the one-time cost. The first request spawns the provider, which takes 50-200ms depending on the runtime. After that, the process stays alive for the daemon's lifetime. Same pattern as model warm-up — you pay once, then it's free.

The one thing to watch: stdout buffering. If your provider doesn't flush after each write, responses get stuck in libc's 4KB buffer. Bun and Node flush by default on \`process.stdout.write()\`. Python needs \`sys.stdout.flush()\` or \`-u\` flag. The template provider handles this correctly.

The \`inferenceMs\` in the metrics object comes from the provider itself, so it reflects actual model time, not IPC time. Vox records the full wall time including IPC, so if the overhead ever became meaningful (it won't), you'd see it in the dashboard.

## What's next

We're shipping a template provider and documentation so anyone can build one. The protocol is stable enough to build on — we don't expect breaking changes to the four methods described here.

If you're already running Vox with Parakeet and want to experiment with a different model, the provider protocol is the way to do it. No fork required, no runtime changes. Just an executable that reads audio and writes text.`,
  },
];

export function getPost(slug: string): BlogPost | undefined {
  return posts.find((p) => p.slug === slug);
}
