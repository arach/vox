# Agent Routing Facts

- choose integration mode before choosing packages
- Apple app process: `VoxCore` + `VoxEngine` (+ optional `VoxAppleSpeech`)
- Bun/Node tool: `voxd` + `@voxd/sdk`
- browser: Vox Companion + `@voxd/client`
- operator workflow: `@voxd/cli`
- canonical SDK types: `packages/client/src/types.ts`
- canonical browser surface: `packages/web-client/src/client.ts`
- canonical CLI syntax: `packages/cli/src/index.ts`
- canonical runtime dispatch: `swift/Sources/VoxService/VoxRuntimeService.swift`
- update docs in the same change when source and prose disagree
- preserve explicit warm-up and telemetry dimensions
