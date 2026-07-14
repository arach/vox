---
title: Agent Guide
description: Canonical routing, source-of-truth, and verification guidance for agents working with Vox.
---

Use this page to choose the right Vox surface before editing code or proposing an integration.

## Choose the integration mode first

| Caller | Use | Do not use by default |
|---|---|---|
| macOS or iOS app process | `VoxCore` + `VoxEngine` | `voxd`, `@voxd/sdk`, `@voxd/client` |
| Bun or Node tool | `voxd` + `@voxd/sdk` | browser bridge |
| Web app or browser extension | Vox Companion + `@voxd/client` | direct WebSocket RPC |
| Operator or benchmark workflow | `@voxd/cli` | custom scripts that hide metrics |

Warm-up is always explicit. Preserve `clientId`, `route`, `modelId`, and `voiceId` where applicable.

## Canonical source map

| Question | Read first |
|---|---|
| Swift package products and platforms | `swift/Package.swift` |
| ASR/TTS provider behavior | `swift/Sources/VoxEngine/` |
| Full Vox companion app | `apps/vox/` |
| Minivox dictation app | `apps/minivox/` |
| Runtime routes and session ownership | `swift/Sources/VoxService/VoxRuntimeService.swift` |
| Companion SDK methods and types | `packages/client/src/client.ts`, `packages/client/src/types.ts` |
| Browser API and HTTP paths | `packages/web-client/src/client.ts`, `packages/web-client/src/types.ts` |
| CLI syntax | `packages/cli/src/index.ts` and `vox help` |
| Public integration guidance | the matching page in `docs/` |

When prose and source disagree, treat the source as current and update the prose in the same change.

## Agent briefs

Major docs pages have a paired compact brief under `docs/agent/*.agent.md`. In the rendered docs, **Copy agent brief** copies that paired file. **Copy markdown** always copies the full human guide.

Use `llms.txt` for routing and `llms-full.txt` when a complete documentation handoff is needed.

## Verification by surface

```bash
bun test packages/client/test packages/cli/test packages/web-client/test

swift test --package-path swift

bun run site:build
bun run docs:check
```

Prefer the narrowest relevant command while iterating. Run the full surface check before publishing.

## Do not assume

- Apple apps need Vox Companion.
- Embed mode records telemetry automatically.
- Warm-up happens implicitly.
- Stop and cancel mean the same thing.
- A copied type shape is current without checking package exports and source types.
- A proposal document describes shipped behavior unless its implementation is confirmed in source.

Start with the [Overview](./overview.md), then open the integration guide selected by the table above.
