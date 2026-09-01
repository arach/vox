import Foundation

public enum PluginCommandError: Error, LocalizedError {
    case empty
    case disallowedLauncher(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Plugin command is empty."
        case .disallowedLauncher(let name):
            return "Plugin command launcher '\(name)' is not allowed."
        case .invalidArgument(let argument):
            return "Plugin command argument is not allowed: \(argument)"
        }
    }
}

public enum PluginCommandValidator {
    public static let allowedLaunchers: Set<String> = [
        "node",
        "bun",
        "npx",
        "bunx",
        "uv",
        "uvx",
        "python3",
        "python"
    ]

    public static func validate(_ command: [String]) throws {
        guard let first = command.first, !first.isEmpty else {
            throw PluginCommandError.empty
        }

        let launcher = URL(fileURLWithPath: first).lastPathComponent
        guard allowedLaunchers.contains(launcher) else {
            throw PluginCommandError.disallowedLauncher(launcher)
        }

        for argument in command {
            if argument.contains("\n")
                || argument.contains(";")
                || argument.contains("|")
                || argument.contains("&")
                || argument.contains("`")
                || argument.contains("$(") {
                throw PluginCommandError.invalidArgument(argument)
            }
        }
    }
}

public enum PluginStore {
    public static func loadInstalled(fileManager: FileManager = .default) -> [ProviderEntry] {
        let root = RuntimePaths.pluginsDirectoryURL()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { directory in
            let url = directory.appendingPathComponent("provider.json")
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try? JSONDecoder().decode(ProviderEntry.self, from: Data(contentsOf: url))
        }.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public static func install(
        _ entry: ProviderEntry,
        fileManager: FileManager = .default
    ) throws {
        if let command = entry.command {
            try PluginCommandValidator.validate(command)
        }

        let directory = pluginDirectory(for: entry.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(
            to: directory.appendingPathComponent("provider.json"),
            options: .atomic
        )
    }

    public static func remove(id: String, fileManager: FileManager = .default) throws {
        let directory = pluginDirectory(for: id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    public static func isInstalled(id: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: pluginDirectory(for: id).appendingPathComponent("provider.json").path)
    }

    public static func pluginDirectory(for id: String) -> URL {
        RuntimePaths.pluginsDirectoryURL().appendingPathComponent(id, isDirectory: true)
    }
}
