import CryptoKit
import Foundation

/// Chrome Web Store packages and Nano's record of installed extensions.
public enum ExtensionPackage {
    public enum Failure: Error, Equatable { case notCRX, truncated, unsupportedVersion(UInt32), unpackFailed(Int32) }

    /// The ZIP archive inside a CRX (versions 2 and 3). WebKit loads the ZIP directly.
    public static func zipData(fromCRX data: Data) throws -> Data {
        guard data.count >= 12, data.prefix(4) == Data("Cr24".utf8) else {
            // Already a ZIP ("PK\u{3}\u{4}")? Pass it through.
            if data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) { return data }
            throw Failure.notCRX
        }
        let version = data.littleEndianUInt32(at: 4)
        let start: Int
        switch version {
        case 3:
            start = 12 + Int(data.littleEndianUInt32(at: 8))
        case 2:
            guard data.count >= 16 else { throw Failure.truncated }
            start = 16 + Int(data.littleEndianUInt32(at: 8)) + Int(data.littleEndianUInt32(at: 12))
        default:
            throw Failure.unsupportedVersion(version)
        }
        guard start < data.count else { throw Failure.truncated }
        return data.subdata(in: data.startIndex + start ..< data.endIndex)
    }

    /// Chrome Web Store extension IDs are 32 letters a–p.
    public static func webStoreID(from text: String) -> String? {
        let candidates = text.split(whereSeparator: { !$0.isLetter })
        return candidates.map(String.init).last { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains($0) } }
    }

    /// Chrome derives an extension's ID from its public key: the first 128 bits of its SHA-256,
    /// one letter a–p per hex digit.
    public static func chromeID(fromKey base64Key: String) -> String? {
        guard let key = Data(base64Encoded: base64Key.filter { !$0.isWhitespace }) else { return nil }
        let letters = SHA256.hash(data: key).prefix(16).flatMap { [$0 >> 4, $0 & 0xF] }
        return String(letters.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    /// The ID Chrome would give the extension in `bundle`: from the manifest's `key`, else from the
    /// item ID the Chrome Web Store records in `_metadata/verified_contents.json`. Native messaging
    /// hosts allow extensions by this ID.
    public static func chromeID(ofBundleAt bundle: URL) -> String? {
        if let data = try? Data(contentsOf: bundle.appendingPathComponent("manifest.json")),
           let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = manifest["key"] as? String {
            return chromeID(fromKey: key)
        }
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("_metadata/verified_contents.json")),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              var payload = (entries.first?["signed_content"] as? [String: Any])?["payload"] as? String else { return nil }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let contents = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let id = contents["item_id"] as? String else { return nil }
        return webStoreID(from: id)
    }

    public static func webStoreDownloadURL(id: String) -> URL? {
        URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0&acceptformat=crx2,crx3&x=id%3D\(id)%26uc")
    }
}

public struct InstalledExtension: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    /// File name inside the extensions folder: a directory (a .zip from before bundles were unpacked).
    /// Empty for Safari extensions, whose files stay in their app.
    public var bundleName: String
    public var isEnabled: Bool
    public var installedAt: Date
    /// The ID the extension has in Chrome, when known. Native messaging hosts allow extensions by it.
    public var chromeID: String?
    /// The bundle identifier of the Safari app extension this loads from, for extensions that come with an app.
    public var safariID: String?
    /// Shown in the toolbar; unpinned extensions are in the toolbar's extensions menu.
    public var isPinned: Bool

    public init(id: String, name: String, version: String, bundleName: String, isEnabled: Bool = true,
                installedAt: Date = Date(), chromeID: String? = nil, safariID: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.version = version
        self.bundleName = bundleName
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.chromeID = chromeID
        self.safariID = safariID
        self.isPinned = isPinned
    }

    /// Lists saved before pinning existed decode with every extension unpinned.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        bundleName = try container.decode(String.self, forKey: .bundleName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        chromeID = try container.decodeIfPresent(String.self, forKey: .chromeID)
        safariID = try container.decodeIfPresent(String.self, forKey: .safariID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

/// The installed-extension list, stored as JSON beside the extension bundles.
public struct ExtensionStore: Sendable {
    public let directory: URL
    private var listURL: URL { directory.appendingPathComponent("extensions.json") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultStore() throws -> ExtensionStore {
        ExtensionStore(directory: try AppSupport.directory("Extensions"))
    }

    public func load() -> [InstalledExtension] {
        guard let data = try? Data(contentsOf: listURL) else { return [] }
        return (try? JSONDecoder().decode([InstalledExtension].self, from: data)) ?? []
    }

    public func save(_ list: [InstalledExtension]) throws {
        try JSONEncoder().encode(list).write(to: listURL, options: .atomic)
    }

    public func bundleURL(for item: InstalledExtension) -> URL {
        directory.appendingPathComponent(item.bundleName)
    }

    /// Copies a folder, or unpacks a ZIP or CRX, into the store under a fresh name.
    public func importBundle(from source: URL) async throws -> String {
        if source.hasDirectoryPath {
            let name = UUID().uuidString
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            return name
        }
        return try await importArchive(try Data(contentsOf: source))
    }

    /// Unpacks a ZIP or CRX into the store under a fresh name.
    public func importArchive(_ data: Data) async throws -> String {
        let archive = directory.appendingPathComponent(".\(UUID().uuidString).zip")
        try ExtensionPackage.zipData(fromCRX: data).write(to: archive, options: .atomic)
        defer { try? FileManager.default.removeItem(at: archive) }
        return try await unpack(archiveAt: archive)
    }

    /// Bundles are folders so Nano can add its compatibility script. bsdtar reads ZIPs and refuses
    /// entries with absolute or `..` paths, so nothing lands outside the new folder.
    private func unpack(archiveAt archive: URL) async throws -> String {
        let name = UUID().uuidString
        let destination = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw ExtensionPackage.Failure.unpackFailed(status)
        }
        return name
    }

    /// Readies a bundle to load: unpacks a ZIP left by an older version, refreshes the compatibility
    /// script, and fills in the Chrome ID. Returns the item as it should be saved.
    public func prepare(_ item: InstalledExtension) async throws -> InstalledExtension {
        // Safari extensions are signed parts of their app; Nano never changes them.
        guard item.safariID == nil else { return item }
        var item = item
        if item.bundleName.hasSuffix(".zip") {
            let name = try await unpack(archiveAt: bundleURL(for: item))
            removeBundle(named: item.bundleName)
            item.bundleName = name
        }
        let bundle = bundleURL(for: item)
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        if item.chromeID == nil { item.chromeID = ExtensionPackage.chromeID(ofBundleAt: bundle) }
        return item
    }

    public func removeBundle(named name: String) {
        // Only ever delete inside the store.
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

private extension Data {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16 | UInt32(self[base + 3]) << 24
    }
}
