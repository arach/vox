import Foundation

enum ParakeetVocabulary {
    static func load(from url: URL) throws -> [Int: String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "VoxEngine", code: 102, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet vocabulary file not found at \(url.path)"
            ])
        }

        let data = try Data(contentsOf: url)

        if let tokenArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
            var vocabulary: [Int: String] = [:]
            vocabulary.reserveCapacity(tokenArray.count)
            for (index, token) in tokenArray.enumerated() {
                vocabulary[index] = token
            }
            return vocabulary
        }

        if let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            var vocabulary: [Int: String] = [:]
            vocabulary.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                if let tokenId = Int(key) {
                    vocabulary[tokenId] = value
                }
            }
            return vocabulary
        }

        throw NSError(domain: "VoxEngine", code: 103, userInfo: [
            NSLocalizedDescriptionKey: "Failed to parse Parakeet vocabulary at \(url.path)"
        ])
    }
}
