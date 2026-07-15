import Testing
@testable import MinivoxSupport

@Suite("Minivox command protocol")
struct MinivoxCommandProtocolTests {
    @Test("No arguments launches Minivox")
    func defaultsToLaunch() throws {
        #expect(try MinivoxCommandInvocation.parse(arguments: []) == .command(.launch))
    }

    @Test("Supported commands parse explicitly")
    func parsesCommands() throws {
        #expect(try MinivoxCommandInvocation.parse(arguments: ["settings"]) == .command(.settings))
        #expect(try MinivoxCommandInvocation.parse(arguments: ["quit"]) == .command(.quit))
        #expect(try MinivoxCommandInvocation.parse(arguments: ["--help"]) == .help)
        #expect(try MinivoxCommandInvocation.parse(arguments: ["--version"]) == .version)
    }

    @Test("Unknown commands fail with guidance")
    func rejectsUnknownCommands() {
        #expect(throws: MinivoxCommandParseError.self) {
            try MinivoxCommandInvocation.parse(arguments: ["toggle"])
        }
    }
}
