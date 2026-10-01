import Foundation

/// Resource lookup for both a signed Apple app and a SwiftPM executable. Signed
/// apps keep resource bundles in Contents/Resources, never in the app root.
public enum SpeechEngineResources {
    public static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        resourceBundle(appBundle: .main)?.url(forResource: name, withExtension: extensionName)
    }

    static let bundleNames = ["Vox_HudsonSpeechEngine.bundle", "HudsonSpeechEngine_HudsonSpeechEngine.bundle"]

    static func resourceBundle(appBundle: Bundle) -> Bundle? {
        if appBundle.bundleURL.pathExtension == "app" {
            guard let resources = appBundle.resourceURL else { return nil }
            // A broken packaged app must not silently use a developer build path. SwiftPM names the
            // bundle after the package that builds it: Vox in Vox's own app, HudsonSpeechEngine when
            // another app (fab) takes this package as a dependency.
            for name in bundleNames {
                if let bundle = Bundle(url: resources.appendingPathComponent(name)) { return bundle }
            }
            return nil
        }
        return .module
    }
}
