import Foundation
import Testing
import VoxCore
@testable import HudsonSpeechEngine

@Suite(.serialized)
struct ProviderRegistryTests {
    @Test("builtin mlx-audio provider resolves bundled script command")
    func builtinMlxAudioCommandUsesBundledScript() throws {
        let command = try BuiltinExternalProvider.mlxAudioCommand(kind: .asr, env: nil)

        #expect(command.count >= 5)
        #expect(command[0] == "/usr/bin/env")
        #expect(command[1] == "python3")
        #expect(command[2] == "-u")
        #expect(command.last == "asr")
        #expect(command[3].hasSuffix("mlx_audio_provider.py"))
    }

    @Test("builtin mlx-audio provider infers VIRTUAL_ENV from python override")
    func builtinMlxAudioEnvironmentInfersVirtualEnv() {
        let env = BuiltinExternalProvider.mlxAudioEnvironment([
            "VOX_MLX_AUDIO_PYTHON": "/tmp/vox-mlx-audio-venv/bin/python3"
        ])

        #expect(env["VOX_MLX_AUDIO_PYTHON"] == "/tmp/vox-mlx-audio-venv/bin/python3")
        #expect(env["VIRTUAL_ENV"] == "/tmp/vox-mlx-audio-venv")
        #expect(env["PYTHONUNBUFFERED"] == "1")
    }

    @Test("builtin mlx-audio provider can opt into uv-managed runner")
    func builtinMlxAudioCommandUsesUvRunnerWhenRequested() throws {
        let command = try BuiltinExternalProvider.mlxAudioCommand(kind: .tts, env: [
            "VOX_MLX_AUDIO_USE_UV": "1"
        ])

        #expect(command.contains("run"))
        #expect(command.contains("mlx-audio"))
        #expect(command.contains("misaki"))
        #expect(command.contains("python"))
        #expect(command.last == "tts")
    }

    @Test("builtin mlx-audio uv runner expands LaunchAgent PATH")
    func builtinMlxAudioEnvironmentExpandsPathForUvRunner() {
        let env = BuiltinExternalProvider.mlxAudioEnvironment([
            "VOX_MLX_AUDIO_USE_UV": "1",
            "PATH": "/usr/bin:/bin"
        ])

        #expect(env["PATH"]?.contains("\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin") == true)
        #expect(env["PATH"]?.contains("/opt/homebrew/bin") == true)
        #expect(env["PYTHONUNBUFFERED"] == "1")
    }

    @Test("ASR registry resolves models discovered from the provider at runtime")
    func providerRegistryDiscoversModelRoutingDynamically() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let otherProviderScript = tempDirectory.appendingPathComponent("other-provider.js")
        try """
        function reply(id, result) {
          process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n");
        }

        process.stdin.setEncoding("utf8");
        let buffer = "";
        process.stdin.on("data", (chunk) => {
          buffer += chunk;
          const lines = buffer.split("\\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.trim()) continue;
            const req = JSON.parse(line);
            switch (req.method) {
              case "models":
                reply(req.id, { models: [{ id: "other:echo", name: "Other Echo", backend: "other", installed: true, preloaded: false, available: true }] });
                break;
              case "transcribe":
                reply(req.id, {
                  modelId: "other:echo",
                  text: "[other] " + String(req.params?.path ?? ""),
                  elapsedMs: 1,
                  metrics: { traceId: "other000", audioDurationMs: 0, inputBytes: 0, wasPreloaded: false, fileCheckMs: 0, modelCheckMs: 0, modelLoadMs: 0, audioLoadMs: 0, audioPrepareMs: 0, inferenceMs: 1, totalMs: 1 }
                });
                break;
              case "install":
              case "preload":
                reply(req.id, { model: { id: "other:echo", name: "Other Echo", backend: "other", installed: true, preloaded: true, available: true } });
                break;
            }
          }
        });
        """
        .write(to: otherProviderScript, atomically: true, encoding: .utf8)

        let providerScript = repositoryRoot()
            .appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent("provider-template", isDirectory: true)
            .appendingPathComponent("index.ts")

        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "other",
                kind: .asr,
                command: ["/usr/bin/env", "bun", "run", otherProviderScript.path]
            ),
            ProviderEntry(
                id: "template",
                kind: .asr,
                command: ["/usr/bin/env", "bun", "run", providerScript.path]
            )
        ])

        let registry = ProviderRegistry(config: config)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let output = try await registry.transcribe(url: audioURL, modelId: "template:echo")

        #expect(output.modelId == "template:echo")
        #expect(output.text.contains(audioURL.path))
        #expect(output.metrics.totalMs >= 0)

        await registry.shutdown()
    }

    @Test("TTS registry resolves models discovered from the provider at runtime")
    func ttsProviderRegistryDiscoversModelRoutingDynamically() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let otherProviderScript = tempDirectory.appendingPathComponent("other-tts-provider.js")
        try """
        function reply(id, result) {
          process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n");
        }

        process.stdin.setEncoding("utf8");
        let buffer = "";
        process.stdin.on("data", (chunk) => {
          buffer += chunk;
          const lines = buffer.split("\\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.trim()) continue;
            const req = JSON.parse(line);
            switch (req.method) {
              case "models":
                reply(req.id, { models: [{ id: "other-tts:v1", name: "Other TTS", backend: "other", installed: true, preloaded: false, available: true }] });
                break;
              case "voices":
                reply(req.id, { voices: [{ id: "other-voice", name: "Other Voice", modelId: "other-tts:v1", backend: "other", available: true, default: true }] });
                break;
              case "preload":
                reply(req.id, { model: { id: "other-tts:v1", name: "Other TTS", backend: "other", installed: true, preloaded: true, available: true } });
                break;
              case "synthesize":
                reply(req.id, {
                  modelId: "other-tts:v1",
                  voiceId: "other-voice",
                  format: "wav",
                  contentType: "audio/wav",
                  audioBase64: "UklGRg==",
                  elapsedMs: 2,
                  metrics: {
                    traceId: "othertts",
                    characterCount: 5,
                    audioDurationMs: 10,
                    outputBytes: 4,
                    wasPreloaded: false,
                    modelCheckMs: 1,
                    modelLoadMs: 0,
                    voiceResolveMs: 1,
                    synthesisMs: 1,
                    totalMs: 2
                  }
                });
                break;
            }
          }
        });
        """
        .write(to: otherProviderScript, atomically: true, encoding: .utf8)

        let scriptURL = tempDirectory.appendingPathComponent("tts-provider.js")
        try """
        function reply(id, result) {
          process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n");
        }

        process.stdin.setEncoding("utf8");
        let buffer = "";
        process.stdin.on("data", (chunk) => {
          buffer += chunk;
          const lines = buffer.split("\\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.trim()) continue;
            const req = JSON.parse(line);
            switch (req.method) {
              case "models":
                reply(req.id, { models: [{ id: "tts-template:v1", name: "Template TTS", backend: "template", installed: true, preloaded: false, available: true }] });
                break;
              case "voices":
                reply(req.id, { voices: [{ id: "voice-1", name: "Voice 1", modelId: "tts-template:v1", backend: "template", available: true, default: true }] });
                break;
              case "preload":
                reply(req.id, { model: { id: "tts-template:v1", name: "Template TTS", backend: "template", installed: true, preloaded: true, available: true } });
                break;
              case "synthesize":
                reply(req.id, {
                  modelId: "tts-template:v1",
                  voiceId: "voice-1",
                  format: "wav",
                  contentType: "audio/wav",
                  audioBase64: "UklGRg==",
                  elapsedMs: 5,
                  metrics: {
                    traceId: "tts12345",
                    characterCount: 5,
                    audioDurationMs: 10,
                    outputBytes: 4,
                    wasPreloaded: false,
                    modelCheckMs: 1,
                    modelLoadMs: 0,
                    voiceResolveMs: 1,
                    synthesisMs: 3,
                    totalMs: 5
                  }
                });
                break;
            }
          }
        });
        """
        .write(to: scriptURL, atomically: true, encoding: .utf8)

        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "other-tts",
                kind: .tts,
                command: ["/usr/bin/env", "bun", "run", otherProviderScript.path]
            ),
            ProviderEntry(
                id: "tts-template",
                kind: .tts,
                command: ["/usr/bin/env", "bun", "run", scriptURL.path]
            )
        ])

        let registry = TTSProviderRegistry(config: config)
        let output = try await registry.synthesize(SynthesisRequest(
            text: "hello",
            modelId: "tts-template:v1"
        ))

        #expect(output.modelId == "tts-template:v1")
        #expect(output.voiceId == "voice-1")
        #expect(output.audioData == Data([0x52, 0x49, 0x46, 0x46]))

        await registry.shutdown()
    }

    private func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
