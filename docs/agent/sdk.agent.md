# SDK Facts

- companion client entrypoint: `packages/client/src/client.ts`
- metrics parser: `packages/client/src/metrics.ts`
- companion client only: Apple apps should embed Swift packages directly instead
- core result types:
  - `FileTranscriptionResult`
  - `SynthesisResult`
- voice metadata type: `VoiceInfo`
- warmup methods exposed: `getWarmupStatus`, `startWarmup`, `scheduleWarmup`
- synthesis methods exposed: `listVoices`, `synthesize`
- ASR method exposed: `transcribeFile`
- live session method exposed: `createLiveSession`
