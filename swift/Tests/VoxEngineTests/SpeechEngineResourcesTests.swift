import Foundation
import Testing
@testable import HudsonSpeechEngine

struct SpeechEngineResourcesTests {
    @Test func packagedAppUsesOnlyContentsResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist: [String: String] = ["CFBundleIdentifier": "test.speech.resources", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: app))
        #expect(SpeechEngineResources.resourceBundle(appBundle: bundle) == nil)
        let resources = contents.appendingPathComponent("Resources/Vox_HudsonSpeechEngine.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: resources.appendingPathComponent("marker.txt"))
        let resolved = try #require(SpeechEngineResources.resourceBundle(appBundle: bundle))
        #expect(resolved.bundleURL.standardizedFileURL == resources.standardizedFileURL)
        #expect(resolved.url(forResource: "marker", withExtension: "txt") != nil)
    }
}
