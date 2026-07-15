import AppKit
import Foundation
import MinivoxSupport

private enum MinivoxCommandLineError: LocalizedError {
    case appBundleNotFound(String)
    case appCouldNotOpen(String)

    var errorDescription: String? {
        switch self {
        case .appBundleNotFound(let path):
            return "Could not find Minivox.app from \(path)."
        case .appCouldNotOpen(let path):
            return "Could not open Minivox at \(path)."
        }
    }
}

private func minivoxAppURL() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["MINIVOX_APP_PATH"], !override.isEmpty {
        let url = URL(fileURLWithPath: override).standardizedFileURL
        guard url.pathExtension == "app" else {
            throw MinivoxCommandLineError.appBundleNotFound(url.path)
        }
        return url
    }

    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let appURL = executable
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    guard appURL.pathExtension == "app" else {
        throw MinivoxCommandLineError.appBundleNotFound(executable.path)
    }
    return appURL
}

private func openMinivox(command: MinivoxCommand) throws {
    let appURL = try minivoxAppURL()

    if command == .settings {
        UserDefaults.standard.set(
            command.rawValue,
            forKey: MinivoxCommandProtocol.pendingCommandDefaultsKey
        )
    }

    var didOpen = NSWorkspace.shared.open(appURL)
    if !didOpen {
        for _ in 0..<10 where !didOpen {
            Thread.sleep(forTimeInterval: 0.1)
            didOpen = NSWorkspace.shared.open(appURL)
        }
    }
    guard didOpen else {
        throw MinivoxCommandLineError.appCouldNotOpen(appURL.path)
    }

    if command == .settings {
        DistributedNotificationCenter.default().postNotificationName(
            MinivoxCommandProtocol.notificationName,
            object: command.rawValue,
            userInfo: nil,
            deliverImmediately: true
        )
        print("Opened Minivox settings.")
    } else {
        print("Minivox is running in the menu bar.")
    }
}

private func quitMinivox() {
    let applications = NSRunningApplication.runningApplications(
        withBundleIdentifier: MinivoxCommandProtocol.bundleIdentifier
    )
    guard !applications.isEmpty else {
        print("Minivox is not running.")
        return
    }

    for application in applications {
        _ = application.terminate()
    }
    print("Minivox quit.")
}

private func minivoxVersion() throws -> String {
    let plistURL = try minivoxAppURL()
        .appendingPathComponent("Contents")
        .appendingPathComponent("Info.plist")
    let data = try Data(contentsOf: plistURL)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    let values = plist as? [String: Any]
    return values?["CFBundleShortVersionString"] as? String ?? "unknown"
}

private func printHelp() {
    print("""
    Minivox

    Usage:
      minivox            Launch Minivox
      minivox settings   Open settings
      minivox quit       Quit Minivox
      minivox version    Print the installed version
    """)
}

do {
    switch try MinivoxCommandInvocation.parse(arguments: Array(CommandLine.arguments.dropFirst())) {
    case .command(.launch):
        try openMinivox(command: .launch)
    case .command(.settings):
        try openMinivox(command: .settings)
    case .command(.quit):
        quitMinivox()
    case .help:
        printHelp()
    case .version:
        print(try minivoxVersion())
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
