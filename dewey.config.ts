/** @type {import('@arach/dewey').DeweyConfig} */
export default {
  project: {
    name: "vox",
    tagline: "Local-first transcription runtime for macOS apps and developer tools",
    type: "monorepo",
    version: "0.1.0",
  },

  agent: {
    criticalContext: [
      "Always solve root cause before looking for workarounds and quick fixes.",
      "Vox is a macOS-first runtime: Swift owns the daemon and audio/transcription engine surface.",
      "The Bun workspace contains the CLI and TypeScript SDK, which communicate with voxd over local WebSocket JSON-RPC.",
      "Performance instrumentation is first-class: preserve clientId, route, and modelId dimensions in telemetry.",
      "Warm-up semantics are part of the public runtime surface and should remain usable for multi-client integrations.",
    ],

    entryPoints: {
      "daemon": "swift/Sources/voxd/main.swift",
      "service": "swift/Sources/VoxService/",
      "engine": "swift/Sources/VoxEngine/",
      "core": "swift/Sources/VoxCore/",
      "sdk": "packages/client/src/",
      "cli": "packages/cli/src/index.ts",
      "docs": "docs/",
      "site": "site/",
    },

    rules: [
      { pattern: "swift/Sources/VoxEngine/*", instruction: "Keep instrumentation and model lifecycle explicit; do not hide warm-up cost in opaque helpers." },
      { pattern: "swift/Sources/VoxService/*", instruction: "Preserve multi-client semantics; clientId should remain available anywhere latency or session ownership matters." },
      { pattern: "packages/client/*", instruction: "SDK APIs should expose the runtime capabilities directly, including metrics and warm-up surfaces." },
      { pattern: "packages/cli/*", instruction: "CLI commands are also operator tools; prefer clear terminal output and measurable benchmarks." },
      { pattern: "site/*", instruction: "Maintain the clean, restrained Vox visual language. Avoid generic startup landing page patterns." },
    ],

    sections: ["overview", "quickstart", "runtime", "sdk", "web-integration", "observability", "architecture", "api"],
  },

  docs: {
    path: "./docs",
    output: "./",
    required: ["overview", "quickstart", "runtime", "sdk", "observability"],
  },

  install: {
    objective: "Clone Vox, build the runtime, and verify local transcription on macOS.",
    doneWhen: {
      command: "bun packages/cli/src/index.ts doctor",
      expectedOutput: "ready: true",
    },
    prerequisites: [
      "macOS 14+",
      "Bun",
      "Swift 6.2+",
      "Microphone permission if testing live transcription",
    ],
    steps: [
      { description: "Clone the repository", command: "git clone https://github.com/arach/vox.git && cd vox" },
      { description: "Install dependencies", command: "bun install" },
      { description: "Build the SDK, CLI, and daemon", command: "bun run build" },
      { description: "Run tests", command: "bun run test" },
      { description: "Verify runtime health", command: "bun packages/cli/src/index.ts doctor" },
    ],
  },
}
