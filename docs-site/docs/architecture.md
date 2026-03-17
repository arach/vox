# Architecture

## Layers

### VoxCore

Shared runtime types and utilities:

- runtime metadata
- transcription metrics
- performance samples
- filesystem paths
- trace utilities

### VoxEngine

Model-facing transcription layer:

- model installation and preload
- audio inspection and preparation
- Parakeet inference
- stage-level timing

### VoxService

Daemon-side orchestration:

- JSON-RPC bridge
- live session coordination
- microphone recording
- warm-up scheduling
- performance sample recording

### TypeScript SDK

`@vox/client` mirrors the runtime capabilities for integrations:

- health
- models
- warm-up
- file transcription
- live sessions
- metrics parsing

### CLI

`vox` is both an operator tool and a dogfooding surface:

- doctor and daemon lifecycle
- model management
- warm benchmarks
- metrics inspection
- dashboard views

## Public Surfaces

- `voxd`
- `@vox/client`
- `vox`
- `site/`

## Responsibility Boundaries

### Swift runtime

Owns:

- daemon lifecycle
- audio loading and preparation
- model lifecycle
- transcription execution
- performance sample recording

### TypeScript SDK

Owns:

- connection lifecycle to the local daemon
- typed request and response shapes
- live-session client ergonomics
- metric parsing for JS and TS consumers

### CLI

Owns:

- operator-facing commands
- machine-readable and human-readable terminal output
- benchmarks, warm-up controls, and dashboard inspection

### Site and docs

Own:

- public explanation of the architecture
- onboarding for contributors and integrators
- OG, landing, and `/docs` presentation

## Data flow

1. Client creates a connection with a stable `clientId`
2. CLI or SDK issues JSON-RPC to `voxd`
3. `VoxService` coordinates model state and route dispatch
4. `VoxEngine` prepares audio and runs Parakeet
5. `VoxCore` types and trace utilities shape the result
6. Runtime appends tagged performance samples for local inspection
