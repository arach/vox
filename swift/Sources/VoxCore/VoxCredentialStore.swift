import CryptoKit
import Foundation
import Security

public struct VoxCredentialState: Sendable, Equatable {
    public let openAIConfigured: Bool
    public let openAIPreview: String?

    public init(openAIConfigured: Bool, openAIPreview: String?) {
        self.openAIConfigured = openAIConfigured
        self.openAIPreview = openAIPreview
    }
}

public struct VoxCredentialStore: Sendable {
    private static let openAIAAD = Data("vox:credentials:openai:v1".utf8)

    private let fileURL: URL
    private let keyURL: URL

    public init(
        fileURL: URL = RuntimePaths.credentialsFileURL(),
        keyURL: URL = RuntimePaths.credentialsKeyURL()
    ) {
        self.fileURL = fileURL
        self.keyURL = keyURL
    }

    public func state() -> VoxCredentialState {
        let key = openAIAPIKey()
        return VoxCredentialState(
            openAIConfigured: key != nil,
            openAIPreview: key.map(Self.preview)
        )
    }

    public func openAIAPIKey() -> String? {
        guard let secret = (try? readStore().openai),
              let keyData = try? readOrCreateKey(),
              let nonceData = Data(base64URLEncoded: secret.iv),
              let ciphertext = Data(base64URLEncoded: secret.ciphertext),
              let tag = Data(base64URLEncoded: secret.tag)
        else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let decrypted = try AES.GCM.open(
                sealedBox,
                using: SymmetricKey(data: keyData),
                authenticating: Self.openAIAAD
            )
            let value = String(decoding: decrypted, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    public func setOpenAIAPIKey(_ value: String) throws {
        let normalized = try Self.normalizeOpenAIKey(value)
        var store = try readStore()
        store.openai = try encrypt(normalized, aad: Self.openAIAAD)
        try writeStore(store)
    }

    public func deleteOpenAIAPIKey() throws {
        var store = try readStore()
        store.openai = nil
        try writeStore(store)
    }

    private static func normalizeOpenAIKey(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-") else {
            throw NSError(domain: "VoxCore", code: 6101, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI API keys should start with sk-."
            ])
        }
        return trimmed
    }

    private static func preview(_ value: String) -> String {
        guard value.count > 10 else { return "configured" }
        return "\(value.prefix(5))...\(value.suffix(4))"
    }

    private func encrypt(_ value: String, aad: Data) throws -> VoxEncryptedSecret {
        let key = try readOrCreateKey()
        let sealed = try AES.GCM.seal(Data(value.utf8), using: SymmetricKey(data: key), authenticating: aad)
        return VoxEncryptedSecret(
            alg: "aes-256-gcm",
            iv: sealed.nonce.data.base64URLEncodedString(),
            tag: sealed.tag.base64URLEncodedString(),
            ciphertext: sealed.ciphertext.base64URLEncodedString()
        )
    }

    private func readStore() throws -> VoxCredentialStoreFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return VoxCredentialStoreFile()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(VoxCredentialStoreFile.self, from: data)
    }

    private func writeStore(_ store: VoxCredentialStoreFile) throws {
        try RuntimePaths.ensureDirectories()
        let data = try JSONEncoder.voxCredentials.encode(store)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func readOrCreateKey() throws -> Data {
        if FileManager.default.fileExists(atPath: keyURL.path),
           let text = try? String(contentsOf: keyURL, encoding: .utf8),
           let key = Data(base64URLEncoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           key.count == 32 {
            return key
        }

        try RuntimePaths.ensureDirectories()
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: "VoxCore", code: 6103, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create credential encryption key."
            ])
        }

        let key = Data(bytes)
        try "\(key.base64URLEncodedString())\n".write(to: keyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return key
    }
}

private struct VoxCredentialStoreFile: Codable {
    var version: Int = 1
    var openai: VoxEncryptedSecret?
}

private struct VoxEncryptedSecret: Codable {
    let alg: String
    let iv: String
    let tag: String
    let ciphertext: String
}

private extension JSONEncoder {
    static var voxCredentials: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension AES.GCM.Nonce {
    var data: Data {
        withUnsafeBytes { Data($0) }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
