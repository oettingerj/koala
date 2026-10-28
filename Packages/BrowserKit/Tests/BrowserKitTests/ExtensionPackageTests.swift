import Foundation
import Testing
@testable import BrowserKit

@Suite struct ExtensionPackageTests {
    private let zip = Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4])

    private func le(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    @Test func stripsCRX3Header() throws {
        let header = Data(repeating: 0xAB, count: 20)
        let crx = Data("Cr24".utf8) + le(3) + le(UInt32(header.count)) + header + zip
        #expect(try ExtensionPackage.zipData(fromCRX: crx) == zip)
    }

    @Test func stripsCRX2Header() throws {
        let key = Data(repeating: 1, count: 5), signature = Data(repeating: 2, count: 7)
        let crx = Data("Cr24".utf8) + le(2) + le(5) + le(7) + key + signature + zip
        #expect(try ExtensionPackage.zipData(fromCRX: crx) == zip)
    }

    @Test func passesZipThroughAndRejectsJunk() throws {
        #expect(try ExtensionPackage.zipData(fromCRX: zip) == zip)
        #expect(throws: ExtensionPackage.Failure.notCRX) { try ExtensionPackage.zipData(fromCRX: Data("hello world!".utf8)) }
        let truncated = Data("Cr24".utf8) + le(3) + le(9999) + zip
        #expect(throws: ExtensionPackage.Failure.truncated) { try ExtensionPackage.zipData(fromCRX: truncated) }
    }

    @Test func findsWebStoreIDs() {
        #expect(ExtensionPackage.webStoreID(from: "https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh")
                == "ddkjiahejlhfcafbddmgiahcphecmpfh")
        #expect(ExtensionPackage.webStoreID(from: "https://example.com/not-an-extension") == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A real ZIP of a folder holding `files`, made with ditto.
    private func zipOf(_ files: [String: String]) throws -> Data {
        let source = try temporaryDirectory(), archive = try temporaryDirectory().appendingPathComponent("x.zip")
        for (path, contents) in files {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        let ditto = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", source.path, archive.path])
        ditto.waitUntilExit()
        return try Data(contentsOf: archive)
    }

    private func manifest(in bundle: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.appendingPathComponent("manifest.json"))) as! [String: Any]
    }

    @Test func derivesChromeIDs() throws {
        #expect(ExtensionPackage.chromeID(fromKey: "bmFubyB0ZXN0IHB1YmxpYyBrZXk=") == "paffohbidfljnphjbcbihkiokcoblomp")
        let bundle = try temporaryDirectory()
        let payload = Data(#"{"item_id":"aeblfdkhhhdcdjpifhhbdiojplfjncoa","item_version":"1"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("_metadata"), withIntermediateDirectories: true)
        try Data(#"[{"signed_content":{"payload":"\#(payload)"}}]"#.utf8).write(to: bundle.appendingPathComponent("_metadata/verified_contents.json"))
        try Data(#"{"name":"X"}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        #expect(ExtensionPackage.chromeID(ofBundleAt: bundle) == "aeblfdkhhhdcdjpifhhbdiojplfjncoa")
        // A manifest key wins over the store's record.
        try Data(#"{"name":"X","key":"bmFubyB0ZXN0IHB1YmxpYyBrZXk="}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        #expect(ExtensionPackage.chromeID(ofBundleAt: bundle) == "paffohbidfljnphjbcbihkiokcoblomp")
    }

    @Test func wrapsBackgroundScriptsOnce() throws {
        let bundle = try temporaryDirectory()
        for folder in ["bg", "lib"] {
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data(#"{"background":{"service_worker":"bg/main.js","type":"module"}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        let background = try manifest(in: bundle)["background"] as! [String: Any]
        #expect(background["service_worker"] as? String == "bg/koala-background.js")
        let wrapper = try String(contentsOf: bundle.appendingPathComponent("bg/koala-background.js"), encoding: .utf8)
        #expect(wrapper == "import \"/koala-compat/compat.js\";\nimport \"/bg/main.js\";\n")
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("koala-compat/compat.js").path))

        try Data(#"{"background":{"service_worker":"sw.js"}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        let classic = try String(contentsOf: bundle.appendingPathComponent("koala-background.js"), encoding: .utf8)
        #expect(classic == "importScripts(\"/koala-compat/compat.js\", \"/sw.js\");\n")

        // A wrapper from an older version, kept in koala-compat/, moves beside the worker it loads.
        let legacy = bundle.appendingPathComponent("koala-compat/background.js")
        try Data("importScripts(\"/koala-compat/compat.js\", \"/lib/sw.js\");\n".utf8).write(to: legacy)
        try Data(#"{"background":{"service_worker":"koala-compat/background.js"}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        #expect((try manifest(in: bundle)["background"] as! [String: Any])["service_worker"] as? String == "lib/koala-background.js")
        #expect(try String(contentsOf: bundle.appendingPathComponent("lib/koala-background.js"), encoding: .utf8)
                == "importScripts(\"/koala-compat/compat.js\", \"/lib/sw.js\");\n")
        #expect(!FileManager.default.fileExists(atPath: legacy.path))

        try Data(#"{"background":{"scripts":["a.js"]}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        #expect((try manifest(in: bundle)["background"] as! [String: Any])["scripts"] as? [String] == ["/koala-compat/compat.js", "a.js"])
    }

    @Test func givesCookieExtensionsNativeMessagingAndSaysSo() throws {
        let bundle = try temporaryDirectory()
        try Data(#"{"permissions":["cookies"],"background":{"service_worker":"sw.js"}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        #expect(try manifest(in: bundle)["permissions"] as? [String] == ["cookies", "nativeMessaging"])
        #expect(ExtensionCompatibility.addedPermissions(inBundleAt: bundle) == ["nativeMessaging"])

        // An extension that asked for native messaging itself keeps it as its own.
        try Data(#"{"permissions":["cookies","nativeMessaging"],"background":{"service_worker":"sw.js"}}"#.utf8).write(to: bundle.appendingPathComponent("manifest.json"))
        try ExtensionCompatibility.apply(toBundleAt: bundle)
        #expect(ExtensionCompatibility.addedPermissions(inBundleAt: bundle).isEmpty)
        #expect(ExtensionCompatibility.script.contains("\"\(ExtensionCompatibility.fetchHost)\"")
                && ExtensionCompatibility.script.contains("\"\(ExtensionCompatibility.consoleHost)\""))
    }

    @Test func unpacksArchivesAndOldZipBundles() async throws {
        let store = ExtensionStore(directory: try temporaryDirectory())
        let archive = try zipOf(["manifest.json": #"{"name":"X","background":{"service_worker":"sw.js"}}"#, "sw.js": ""])
        let name = try await store.importArchive(archive)
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("\(name)/sw.js").path))
        await #expect(throws: ExtensionPackage.Failure.self) { try await store.importArchive(zip) }

        // A bundle saved as a ZIP by an older version becomes a wrapped folder.
        let oldName = "old.zip"
        try archive.write(to: store.directory.appendingPathComponent(oldName))
        let item = try await store.prepare(InstalledExtension(id: "x", name: "X", version: "1", bundleName: oldName))
        #expect(!item.bundleName.hasSuffix(".zip"))
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(oldName).path))
        #expect((try manifest(in: store.bundleURL(for: item))["background"] as! [String: Any])["service_worker"] as? String
                == "koala-background.js")
    }

    @Test func storeRoundTripsAndRefusesEscapes() async throws {
        let directory = try temporaryDirectory()
        let store = ExtensionStore(directory: directory)
        let name = try await store.importArchive(try zipOf(["manifest.json": "{}"]))
        let item = InstalledExtension(id: "x", name: "X", version: "1", bundleName: name)
        try store.save([item])
        #expect(store.load() == [item])
        store.removeBundle(named: "../\(directory.lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: directory.path))
        store.removeBundle(named: name)
        #expect(!FileManager.default.fileExists(atPath: store.bundleURL(for: item).path))
    }

    @Test func listsFromBeforePinningLoadUnpinned() throws {
        let store = ExtensionStore(directory: try temporaryDirectory())
        let pinned = InstalledExtension(id: "x", name: "X", version: "1", bundleName: "b", isPinned: true)
        try store.save([pinned])
        #expect(store.load() == [pinned])
        var entry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pinned)) as! [String: Any]
        entry["isPinned"] = nil
        try JSONSerialization.data(withJSONObject: [entry]).write(to: store.directory.appendingPathComponent("extensions.json"))
        #expect(store.load().map(\.isPinned) == [false])
    }
}
