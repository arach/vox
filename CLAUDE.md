# CLAUDE.md

Project guidance for AI coding agents working in Vox.

## Project Identity

Vox is a local-first transcription runtime for macOS apps and developer tools.

It combines:

- Swift runtime services and daemon code in `swift/`
- a TypeScript SDK in `packages/client/`
- a Bun CLI in `packages/cli/`
- Dewey docs in `docs/`
- a public site and docs UI in `site/`

## Non-Negotiables

- Solve root cause before looking for workarounds and quick fixes.
- Preserve telemetry dimensions like `clientId`, `route`, and `modelId`.
- Treat warm-up as a public runtime capability, not an internal side effect.
- Keep CLI output operator-friendly and measurable.
- Preserve the restrained Vox visual style in the site.

## Commands

```bash
bun install
bun run build
bun run build:all
bun run test
bun run test:e2e
bun run site:dev
bun run site:build
bun run docs:generate
```
