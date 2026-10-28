import AppKit
import BrowserKit
import os

/// Koala left the App Sandbox; what it saved while sandboxed is still in its container.
enum DataMigration {
    private static let doneKey = "CopiedSandboxContainer"

    /// Copies the container's data out once. Runs before anything opens the database, the session,
    /// or WebKit, so they all start from the copied files. Returns false when Koala should quit instead.
    static func copyFromSandboxContainer() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey), let bundleID = Bundle.main.bundleIdentifier else { return true }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let migration = SandboxMigration(container: library.appendingPathComponent("Containers/\(bundleID)/Data/Library"),
                                         library: library, bundleID: bundleID, supportFolder: AppSupport.folderName)
        let failures = migration.copy()
        guard failures.isEmpty else {
            let log = Logger(subsystem: "com.joshoettinger.koala", category: "migration")
            for failure in failures { log.error("Couldn’t copy from the sandbox container: \(failure, privacy: .public)") }
            // Starting anyway would create fresh files, and the copy never overwrites, so the old data
            // would never come over. Only the person can decide to leave it behind.
            guard askToStartWithoutOldData() else { return false }
            defaults.set(true, forKey: doneKey)
            return true
        }
        // Defaults go through the defaults system, not a file copy, so nothing caches a stale plist.
        if let old = NSDictionary(contentsOf: migration.preferences) as? [String: Any] {
            for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: doneKey)
        return true
    }

    /// macOS guards app containers, and an ad-hoc signed build counts as a different app each time
    /// it's rebuilt, so the copy can be refused. Full Disk Access lifts that.
    private static func askToStartWithoutOldData() -> Bool {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Koala"
        let alert = NSAlert()
        alert.messageText = "\(name) can’t bring over your data yet"
        alert.informativeText = """
            macOS is blocking \(name) from reading the folder it used before, which holds your history, tabs, \
            extensions, and website data. Turn on \(name) in Privacy & Security › Full Disk Access, then open \(name) \
            again. You can turn it off after.
            """
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Start Without Old Data")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            return false
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }
}
