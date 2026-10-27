import Foundation
import Testing
@testable import BrowserKit

@Suite struct SafariExtensionsTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safari-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An app in `folder` holding one app extension at `point` with `permissions` in its manifest.
    private func makeApp(_ name: String, in folder: URL, id: String, point: String = SafariExtensions.extensionPoint,
                         permissions: [String] = []) throws {
        let appex = folder.appendingPathComponent("\(name).app/Contents/PlugIns/Ext.appex/Contents")
        try FileManager.default.createDirectory(at: appex.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": id, "NSExtension": ["NSExtensionPointIdentifier": point]]
        try info.write(to: appex.appendingPathComponent("Info.plist"))
        try JSONSerialization.data(withJSONObject: ["manifest_version": 3, "permissions": permissions])
            .write(to: appex.appendingPathComponent("Resources/manifest.json"))
    }

    @Test func findsSafariWebExtensionsInApps() throws {
        let system = try temporaryDirectory(), user = try temporaryDirectory()
        try makeApp("Zed", in: system, id: "z.ext", permissions: ["storage"])
        try makeApp("Alpha", in: system, id: "a.ext", permissions: ["nativeMessaging"])
        try makeApp("Widget", in: system, id: "w.ext", point: "com.apple.widgetkit-extension")
        try makeApp("Zed Copy", in: user, id: "z.ext")
        try makeApp("Mine", in: user, id: "m.ext")

        let found = SafariExtensions.find(in: [system, user, system.appendingPathComponent("missing")])
        #expect(found.map(\.id) == ["a.ext", "m.ext", "z.ext"])
        #expect(found.map(\.appName) == ["Alpha", "Mine", "Zed"])
        #expect(found.map(\.usesNativeMessaging) == [true, false, false])
        #expect(found[2].url.path.hasSuffix("Zed.app/Contents/PlugIns/Ext.appex"))
    }

    @Test func storeLeavesSafariExtensionsAlone() async throws {
        let directory = try temporaryDirectory()
        try Data("keep".utf8).write(to: directory.appendingPathComponent("marker"))
        let store = ExtensionStore(directory: directory)
        let item = InstalledExtension(id: "x", name: "X", version: "1", bundleName: "", safariID: "a.ext")
        #expect(try await store.prepare(item) == item)
        store.removeBundle(named: item.bundleName)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("marker").path))

        // Lists saved before Safari extensions existed still load.
        try Data(#"[{"id":"y","name":"Y","version":"1","bundleName":"b","isEnabled":true,"installedAt":0}]"#.utf8)
            .write(to: directory.appendingPathComponent("extensions.json"))
        #expect(store.load().map(\.safariID) == [nil])
    }
}
