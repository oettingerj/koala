import Foundation

/// Where Nano keeps its own files: Application Support/<app name>. Release ("Nano") and Debug
/// ("Nano Dev") builds have different names, so they never share history, sessions, or extensions.
public enum AppSupport {
    public static var folderName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nano"
    }

    /// The folder, or a subfolder of it, created if needed.
    public static func directory(_ subfolder: String? = nil) throws -> URL {
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
        if let subfolder { directory.appendPathComponent(subfolder, isDirectory: true) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Nano used to run in the App Sandbox, which kept its data in its container. This copies that data
/// to where an unsandboxed app keeps it. It copies and never overwrites, so the container stays
/// intact for a rollback.
public struct SandboxMigration: Sendable {
    /// The container's Library folder: ~/Library/Containers/<bundle ID>/Data/Library.
    public let container: URL
    /// The user's Library folder.
    public let library: URL
    public let bundleID: String
    public let supportFolder: String

    public init(container: URL, library: URL, bundleID: String, supportFolder: String) {
        self.container = container
        self.library = library
        self.bundleID = bundleID
        self.supportFolder = supportFolder
    }

    /// Container path, then the path outside it. In the container WebKit's folders are not per app.
    var copies: [(from: URL, to: URL)] {
        [(container.appendingPathComponent("Application Support/Nano"), library.appendingPathComponent("Application Support/\(supportFolder)")),
         (container.appendingPathComponent("WebKit"), library.appendingPathComponent("WebKit/\(bundleID)")),
         (container.appendingPathComponent("HTTPStorages/\(bundleID)"), library.appendingPathComponent("HTTPStorages/\(bundleID)")),
         (container.appendingPathComponent("Cookies/Cookies.binarycookies"), library.appendingPathComponent("Cookies/\(bundleID).binarycookies"))]
    }

    /// The sandboxed app's defaults.
    public var preferences: URL { container.appendingPathComponent("Preferences/\(bundleID).plist") }

    /// Copies whatever the container has that isn't already in place. Returns what failed, empty when
    /// everything is in place, so the caller can try again next launch.
    public func copy() -> [String] {
        let files = FileManager.default
        guard files.fileExists(atPath: container.path) else { return [] }
        // macOS may refuse to list a container (App Data protection); that isn't "nothing to copy".
        do { _ = try files.contentsOfDirectory(atPath: container.path) } catch { return ["\(container.path): \(error.localizedDescription)"] }
        var failures: [String] = []
        for (from, to) in copies where files.fileExists(atPath: from.path) && !files.fileExists(atPath: to.path) {
            // Copy beside the destination, then rename, so a failed copy never looks finished.
            let staging = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).copying")
            do {
                try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? files.removeItem(at: staging)
                try files.copyItem(at: from, to: staging)
                try files.moveItem(at: staging, to: to)
            } catch {
                try? files.removeItem(at: staging)
                failures.append("\(from.path): \(error.localizedDescription)")
            }
        }
        return failures
    }
}
