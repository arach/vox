import Foundation
import Testing
import VoxCore
@testable import HudsonSpeechEngine

struct TTSDefaultProviderConfigTests {
    @Test("alias-aware merging keeps configured magpie, groq-tts, and google-tts families")
    func mergingRespectsProviderFamilyAliases() {
        let magpie = ProviderEntry(
            id: "magpie",
            kind: .tts,
            builtin: true,
            models: ["custom-magpie-route"],
            env: ["NV_API_KEY": "configured-magpie"]
        )
        let groq = ProviderEntry(
            id: "groq-tts",
            kind: .tts,
            builtin: true,
            models: ["custom-groq-route"],
            env: ["GROQ_API_KEY": "configured-groq"]
        )
        let google = ProviderEntry(
            id: "google-tts",
            kind: .tts,
            builtin: true,
            models: ["custom-gemini-route"],
            env: ["GOOGLE_API_KEY": "configured-google"]
        )
        let asr = ProviderEntry(id: "parakeet", kind: .asr, builtin: true, models: ["parakeet:v3"])

        let merged = TTSDefaultProviderConfig.mergingMissingDefaults(into: ProvidersConfig(
            providers: [asr, magpie, groq, google]
        ))
        let tts = merged.providers.filter { $0.resolvedKind == .tts }
        let ids = tts.map(\.id)

        #expect(ids.contains("magpie"))
        #expect(ids.contains("groq-tts"))
        #expect(ids.contains("google-tts"))
        #expect(!ids.contains("nvidia"))
        #expect(!ids.contains("groq"))
        #expect(!ids.contains("gemini"))
        #expect(tts.first(where: { $0.id == "magpie" })?.env?["NV_API_KEY"] == "configured-magpie")
        #expect(tts.first(where: { $0.id == "groq-tts" })?.models == ["custom-groq-route"])
        #expect(tts.first(where: { $0.id == "google-tts" })?.env?["GOOGLE_API_KEY"] == "configured-google")
        #expect(ids.contains("openai-tts"))
        #expect(ids.contains("avspeech"))
    }

    @Test("alias-aware merging covers every builtin TTS family")
    func mergingCoversEveryFamily() {
        let aliases: [(String, TTSProviderFamily)] = [
            ("openai", .openai),
            ("eleven-labs", .elevenlabs),
            ("minimax-tts", .minimax),
            ("nvidia-magpie", .nvidia),
            ("groq-tts", .groq),
            ("gemini-tts", .gemini),
            ("apple-tts", .avspeech)
        ]

        for (alias, family) in aliases {
            let merged = TTSDefaultProviderConfig.mergingMissingDefaults(into: ProvidersConfig(
                providers: [
                    ProviderEntry(
                        id: alias,
                        kind: .tts,
                        builtin: true,
                        models: ["custom-\(family.rawValue)"],
                        env: ["KEEP": "yes"]
                    )
                ]
            ))
            let ttsIds = merged.providers.filter { $0.resolvedKind == .tts }.map(\.id)
            #expect(ttsIds.contains(alias), "Expected alias \(alias) to remain")
            #expect(
                !ttsIds.contains(family.canonicalProviderId) || alias == family.canonicalProviderId,
                "Canonical \(family.canonicalProviderId) should not be appended over alias \(alias)"
            )
            #expect(merged.providers.first(where: { $0.id == alias })?.env?["KEEP"] == "yes")
        }
    }
}
