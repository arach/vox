<p align="center">
  <img src="https://raw.githubusercontent.com/arach/vox/main/assets/readme/client.svg" alt="Vox Client — local transcription for web apps" width="100%" />
</p>

# @voxd/client

Add local transcription to a web app. The browser client connects to [Vox Companion](https://voxd.cc/download) on the user's Mac—no hosted speech server required.

## Install

```bash
bun add @voxd/client
```

Or with npm:

```bash
npm install @voxd/client
```

## Quick start

```ts
import { createVoxdClient } from "@voxd/client";

const vox = createVoxdClient({ clientId: "my-web-app" });

if (await vox.probe()) {
  const result = await vox.transcribe({
    audio: audioBlob,
    language: "en",
    timestamps: true,
  });

  console.log(result.text);
  console.log(result.words);
}
```

Your app owns microphone permission and recording. Pass the finished `Blob`, `File`, or `ArrayBuffer` to Vox.

## Check for Companion

`probe()` is safe to call when Vox Companion is not installed.

```ts
if (!(await vox.probe())) {
  // Show your normal fallback or an install link.
}
```

If Companion is installed but closed, `vox.launch()` opens it.

## Align audio from a URL

```ts
const alignment = await vox.align({
  source: { audioUrl: "https://example.com/audio.mp3" },
});

console.log(alignment.words);
```

## Good to know

- The default bridge is `http://127.0.0.1:43115`.
- All routes except `/health` check the page origin.
- Live sessions have separate stop and cancel operations.
- Optional Web Audio effects are available from `@voxd/client/fx`.

## Choose the right package

- Browser: `@voxd/client`
- Bun or Node: [`@voxd/sdk`](https://www.npmjs.com/package/@voxd/sdk)
- Terminal: [`@voxd/cli`](https://www.npmjs.com/package/@voxd/cli)
- macOS or iOS app: embed `VoxCore` and `VoxEngine`

## Learn more

- [Web integration guide](https://voxd.cc/docs/web-integration/)
- [API reference](https://voxd.cc/docs/api/)
- [Download Vox Companion](https://voxd.cc/download)

## License

[MIT](./LICENSE)
