# Web Integration Facts

- package: `@voxd/client`
- transport: local HTTP bridge, default `http://127.0.0.1:43115`
- call `probe()` before depending on Companion availability
- use `transcribe()` for browser-owned audio data
- use `align()` when Companion should fetch an audio URL
- live sessions use `createLiveSession()` and distinct stop/cancel semantics
- browser client does not own microphone capture or permissions
- all bridge endpoints except `/health` are origin-gated
- preserve a stable `clientId`
- use `launch()` only as an installed-but-not-running recovery path
- canonical surface: `packages/web-client/src/client.ts`
