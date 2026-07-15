<p align="center">
  <img src="https://raw.githubusercontent.com/arach/vox/main/assets/readme/sdk.svg" alt="Vox SDK — local transcription and text-to-speech for Bun and Node" width="100%" />
</p>

# @voxd/sdk

Use Vox transcription and text-to-speech from Bun or Node. The SDK connects to [Vox Companion](https://voxd.cc/download), which runs the speech models on the Mac.

## Install

```bash
bun add @voxd/sdk
```

Or with npm:

```bash
npm install @voxd/sdk
```

Requires Node 22+ or Bun, plus Vox Companion running on the same Mac.

## Quick start

```ts
import { VoxClient } from "@voxd/sdk";

const vox = new VoxClient({ clientId: "my-tool" });
await vox.connect();

const transcript = await vox.transcribeFile("/tmp/sample.wav");
console.log(transcript.text);

const speech = await vox.synthesize("Hello from Vox");
console.log(speech.audioBytes);

vox.disconnect();
```

## Warm up before a request

Warm-up is explicit, so your app decides when to spend the startup cost.

```ts
await vox.startWarmup("parakeet:v3");
const result = await vox.transcribeFile("/tmp/sample.wav", "parakeet:v3");

console.log(result.text);
console.log(result.metrics?.totalMs);
```

## Main API

- `connect()` and `disconnect()`
- `transcribeFile()` and `annotateFile()`
- `listVoices()` and `synthesize()`
- `startWarmup()`, `scheduleWarmup()`, and `getWarmupStatus()`
- `createLiveSession()`
- `listHistory()` and `deleteHistoryRecord()`
- `doctor()` and `health()`

Use a stable `clientId` so metrics and sessions can be traced back to your tool.

## Choose the right package

- Bun or Node: `@voxd/sdk`
- Browser: [`@voxd/client`](https://www.npmjs.com/package/@voxd/client)
- Terminal: [`@voxd/cli`](https://www.npmjs.com/package/@voxd/cli)
- macOS or iOS app: embed `VoxCore` and `VoxEngine`

## Learn more

- [SDK guide](https://voxd.cc/docs/sdk/)
- [API reference](https://voxd.cc/docs/api/)
- [Download Vox Companion](https://voxd.cc/download)

## License

[MIT](./LICENSE)
