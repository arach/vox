import Foundation
import os

public enum VoxLog {
    private static let subsystem = "dev.vox"

    public static let core = Logger(subsystem: subsystem, category: "core")
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let service = Logger(subsystem: subsystem, category: "service")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let daemon = Logger(subsystem: subsystem, category: "daemon")
}
