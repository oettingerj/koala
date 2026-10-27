import Foundation

/// Turns a server-suggested filename into a safe, unique file in the downloads folder.
/// The name comes from the network, so it is treated as hostile.
public enum DownloadNaming {
    public static func sanitize(_ suggested: String?) -> String {
        var name = (suggested ?? "").precomposedStringWithCanonicalMapping
        // Path separators and control characters never survive; ":" is a separator to Finder.
        name = String(name.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == "\\" || scalar == ":" || CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar) { return "-" }
            return Character(scalar)
        })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // No hidden files and no "." or "..".
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "download" }
        // Keep the extension when shortening to a filesystem-safe length.
        if name.utf8.count > 200 {
            let ext = (name as NSString).pathExtension
            var stem = (name as NSString).deletingPathExtension
            while stem.utf8.count + ext.utf8.count + 1 > 200 { stem.removeLast() }
            name = ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        return name
    }

    /// `directory/name`, or `name 2`, `name 3`… when it already exists.
    public static func uniqueURL(for name: String, in directory: URL, exists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path)
    }) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard exists(candidate) else { return candidate }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let next = directory.appendingPathComponent(ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)")
            if !exists(next) { return next }
            index += 1
        }
    }
}
