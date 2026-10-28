import Foundation

/// Chrome builds of extensions call Chrome APIs WebKit doesn't implement, often unguarded at startup,
/// which stops the background script before it does anything. Koala loads a script ahead of the
/// background script that fills those gaps with inert stand-ins.
public enum ExtensionCompatibility {
    static let folder = "koala-compat"
    static let scriptPath = "/\(folder)/compat.js"
    /// The wrapper sits beside the original worker: a classic worker resolves relative `importScripts`
    /// paths against its own URL, so a wrapper elsewhere breaks workers that import their siblings.
    static let wrapperName = "koala-background.js"
    /// Where older versions put the wrapper.
    static let legacyWrapperPath = "\(folder)/background.js"
    /// The native host name the compat script sends console errors to; Koala logs them instead of launching anything.
    public static let consoleHost = "koala.console"
    /// The native host name the compat script sends background requests to; Koala makes them with the site's cookies.
    public static let fetchHost = "koala.fetch"
    /// Manifest key listing permissions Koala added, which the extension never asked the user for.
    static let addedPermissionsKey = "koala_added_permissions"

    /// Writes the script into `bundle` and points the manifest's background at it. Safe to repeat;
    /// a bundle that is already wrapped only gets the current script.
    public static func apply(toBundleAt bundle: URL) throws {
        let manifestURL = bundle.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var background = manifest["background"] as? [String: Any] else { return }
        let directory = bundle.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: directory.appendingPathComponent("compat.js"), options: .atomic)

        var changed = false
        if var worker = (background["service_worker"] as? String).map({ String($0.drop { $0 == "/" }) }) {
            let legacyWrapper = bundle.appendingPathComponent(legacyWrapperPath)
            if worker == legacyWrapperPath, let original = legacyOriginal(in: legacyWrapper) {
                worker = original
                try? FileManager.default.removeItem(at: legacyWrapper)
            }
            if (worker as NSString).lastPathComponent != wrapperName {
                let wrapperPath = ((worker as NSString).deletingLastPathComponent as NSString).appendingPathComponent(wrapperName)
                let original = try specifier("/" + worker)
                let source = background["type"] as? String == "module"
                    ? "import \(try specifier(scriptPath));\nimport \(original);\n"
                    : "importScripts(\(try specifier(scriptPath)), \(original));\n"
                try Data(source.utf8).write(to: bundle.appendingPathComponent(wrapperPath), options: .atomic)
                background["service_worker"] = wrapperPath
                changed = true
            }
        }
        if var scripts = background["scripts"] as? [String], scripts.first != scriptPath {
            scripts.insert(scriptPath, at: 0)
            background["scripts"] = scripts
            changed = true
        }
        // Extensions that read cookies work with site sessions, which their background requests carry only
        // when Koala makes them (see compat.js), and the compat script reaches Koala through native messaging.
        var permissions = manifest["permissions"] as? [String] ?? []
        if permissions.contains("cookies"), !permissions.contains("nativeMessaging") {
            permissions.append("nativeMessaging")
            manifest["permissions"] = permissions
            manifest[addedPermissionsKey] = ["nativeMessaging"]
            changed = true
        }
        guard changed else { return }
        manifest["background"] = background
        let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try output.write(to: manifestURL, options: .atomic)
    }

    /// Permissions in the bundle's manifest that Koala added rather than the extension's author.
    public static func addedPermissions(inBundleAt bundle: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(manifest[addedPermissionsKey] as? [String] ?? [])
    }

    /// The worker an older wrapper loads: the last quoted path in it, without the leading slash.
    private static func legacyOriginal(in wrapper: URL) -> String? {
        guard let source = try? String(contentsOf: wrapper, encoding: .utf8) else { return nil }
        let quoted = source.split(separator: "\"", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }
        return quoted.last.map { String($0.element.drop { $0 == "/" }) }
    }

    /// A quoted JavaScript string for a script path.
    private static func specifier(_ path: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: path, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// The script, from compat.js beside this file.
    static let script: String = {
        guard let url = Bundle.module.url(forResource: "compat", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { preconditionFailure("compat.js is missing from BrowserKit's resources") }
        return source
    }()
}
