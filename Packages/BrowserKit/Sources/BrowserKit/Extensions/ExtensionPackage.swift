import Foundation

/// Chrome Web Store packages and Nano's record of installed extensions.
public enum ExtensionPackage {
    public enum Failure: Error, Equatable { case notCRX, truncated, unsupportedVersion(UInt32) }

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

    public static func webStoreDownloadURL(id: String) -> URL? {
        URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0&acceptformat=crx2,crx3&x=id%3D\(id)%26uc")
    }
}

public struct InstalledExtension: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    /// File name inside the extensions folder: a directory or a .zip.
    public var bundleName: String
    public var isEnabled: Bool
    public var installedAt: Date

    public init(id: String, name: String, version: String, bundleName: String, isEnabled: Bool = true, installedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.version = version
        self.bundleName = bundleName
        self.isEnabled = isEnabled
        self.installedAt = installedAt
    }
}

/// The installed-extension list, stored as JSON beside the extension bundles.
public struct ExtensionStore: Sendable {
    public let directory: URL
    private var listURL: URL { directory.appendingPathComponent("extensions.json") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultStore() throws -> ExtensionStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Nano/Extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ExtensionStore(directory: directory)
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

    /// Copies a folder or archive into the store under a fresh name. CRX files are unwrapped.
    public func importBundle(from source: URL) throws -> String {
        let id = UUID().uuidString
        if source.hasDirectoryPath {
            let name = id
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            return name
        }
        let data = try ExtensionPackage.zipData(fromCRX: try Data(contentsOf: source))
        let name = id + ".zip"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func importArchive(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".zip"
        try ExtensionPackage.zipData(fromCRX: data).write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func removeBundle(named name: String) {
        // Only ever delete inside the store.
        guard !name.contains("/"), !name.hasPrefix(".") else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

private extension Data {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16 | UInt32(self[base + 3]) << 24
    }
}
