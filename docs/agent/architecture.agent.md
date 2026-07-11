# Architecture Facts

- `VoxCore`: shared types, paths, traces, and performance records
- `VoxEngine`: provider routing, model lifecycle, audio preparation, ASR, annotation, and TTS
- `VoxService`: daemon RPC, sessions, warm-up, capture, and telemetry
- `VoxBridge`: narrow browser-facing HTTP transport
- `@voxd/sdk`: WebSocket companion client for Bun/Node
- `@voxd/client`: HTTP browser client
- `@voxd/cli`: operator and benchmark surface
- Swift owns the embeddable engine and companion transport surfaces
- keep model lifecycle and warm-up explicit across layers
