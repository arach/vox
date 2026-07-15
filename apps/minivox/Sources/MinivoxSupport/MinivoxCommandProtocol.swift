import Foundation

public enum MinivoxCommand: String, Equatable, Sendable {
    case launch
    case settings
    case quit
}

public enum MinivoxCommandInvocation: Equatable, Sendable {
    case command(MinivoxCommand)
    case help
    case version

    public static func parse(arguments: [String]) throws -> MinivoxCommandInvocation {
        switch arguments {
        case []:
            return .command(.launch)
        case ["launch"]:
            return .command(.launch)
        case ["settings"]:
            return .command(.settings)
        case ["quit"]:
            return .command(.quit)
        case ["help"], ["--help"], ["-h"]:
            return .help
        case ["version"], ["--version"], ["-v"]:
            return .version
        default:
            throw MinivoxCommandParseError(arguments: arguments)
        }
    }
}

public struct MinivoxCommandParseError: LocalizedError, Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }

    public var errorDescription: String? {
        let value = arguments.isEmpty ? "(missing)" : arguments.joined(separator: " ")
        return "Unknown Minivox command: \(value). Run `minivox help`."
    }
}

public enum MinivoxCommandProtocol {
    public static let bundleIdentifier = "cc.voxd.minivox"
    public static let notificationName = Notification.Name("cc.voxd.minivox.command")
    public static let pendingCommandDefaultsKey = "minivox.pendingCommand"
}
