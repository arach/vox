import Foundation

/// Resource lookup for both a signed Apple app and a SwiftPM executable. Signed
/// apps keep resource bundles in Contents/Resources, never in the app root.
public enum SpeechEngineResources {
    public static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        resourceBundle(appBundle: .main)?.url(forResource: name, withExtension: extensionName)
    }

    static func resourceBundle(appBundle: Bundle) -> Bundle? {
        if appBundle.bundleURL.pathExtension == "app" {
            guard let resources = appBundle.resourceURL else { return nil }
            // A broken packaged app must not silently use a developer build path.
            return Bundle(url: resources.appendingPathComponent("Vox_HudsonSpeechEngine.bundle"))
        }
        return .module
    }
}
