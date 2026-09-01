# SDK Facts

- companion client entrypoint: `packages/client/src/client.ts`
- metrics parser: `packages/client/src/metrics.ts`
- companion client only: Apple apps should embed Swift packages directly instead
- core result types:
  - `FileTranscriptionResult`
  - `FileAnnotationResult`
  - `SynthesisResult`
- voice metadata type: `VoiceInfo`
- warmup methods exposed: `getWarmupStatus`, `startWarmup`, `scheduleWarmup`
- synthesis methods exposed: `listVoices`, `synthesize`
- ASR method exposed: `transcribeFile`
- annotation method exposed: `annotateFile`
- live session method exposed: `createLiveSession`; it returns `VoxLiveSession` synchronously
- synthesis can return optional `speechTiming`; read the types in `packages/client/src/types.ts` before duplicating shapes
- per-request `credentials` are allowlisted for OpenAI, NVIDIA Magpie, Groq, and Gemini/Google only
