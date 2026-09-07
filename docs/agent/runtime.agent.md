# Runtime Facts

- health methods: `health`, `doctor.run`
- warmup methods: `warmup.status`, `warmup.start`, `warmup.schedule`
- ASR model routes: `models.list`, `models.install`, `models.preload`, `models.catalog`, `models.refreshCatalog`
- ASR file route: `transcribe.file`
- annotation route: `annotate.file`
- ASR live routes: `transcribe.startSession`, `transcribe.sessionStatus`, `transcribe.stopSession`, `transcribe.cancelSession`
- TTS routes: `synthesize.voices`, `synthesize.generate`, `synthesize.startSession`, `synthesize.sessionStatus`, `synthesize.cancel`
- performance log path: `~/.vox/performance.jsonl`
- runtime metadata path: `~/.vox/runtime.json`
- model catalog cache: `~/.vox/cache/models-catalog.json`
- plugin store: `~/.vox/plugins/<id>/provider.json`
- browser bridge endpoints other than `/health` are origin-gated
- session ownership includes both `connectionID` and `clientId`; stop and cancel are not interchangeable
