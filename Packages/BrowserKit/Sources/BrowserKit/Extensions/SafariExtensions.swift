import Foundation

/// Safari web extensions ship as app extensions inside Mac apps. WebKit loads them straight from the
/// app's bundle, so Koala finds them where apps live instead of copying them.
public enum SafariExtensions {
    static let extensionPoint = "com.apple.Safari.web-extension"

    public struct Found: Equatable, Identifiable, Sendable {
        /// The app extension's bundle identifier.
        public let id: String
        /// The app that ships it, which is how people recognize it.
        public let appName: String
        public let url: URL
        /// Its messages go to a handler inside the app extension, which Koala can't launch yet.
        public let usesNativeMessaging: Bool
    }

    /// Where apps are installed for everyone and for the current user.
    public static func appFolders(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// Safari web extensions inside the apps directly in `folders`, sorted by app name.
    public static func find(in folders: [URL]) -> [Found] {
        let files = FileManager.default
        var found: [Found] = []
        for folder in folders {
            let apps = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let plugIns = app.appendingPathComponent("Contents/PlugIns", isDirectory: true)
                for appex in (try? files.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? [] where appex.pathExtension == "appex" {
                    if let item = inspect(appex, appName: app.deletingPathExtension().lastPathComponent) { found.append(item) }
                }
            }
        }
        // The same extension in both folders: the first folder wins.
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
            .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    private static func inspect(_ appex: URL, appName: String) -> Found? {
        guard let info = NSDictionary(contentsOf: appex.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String,
              (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == extensionPoint,
              let data = try? Data(contentsOf: appex.appendingPathComponent("Contents/Resources/manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let permissions = manifest["permissions"] as? [String] ?? []
        return Found(id: id, appName: appName, url: appex, usesNativeMessaging: permissions.contains("nativeMessaging"))
    }
}
