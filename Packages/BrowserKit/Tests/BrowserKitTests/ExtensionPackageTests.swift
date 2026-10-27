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

    @Test func storeRoundTripsAndRefusesEscapes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ExtensionStore(directory: directory)
        let name = try store.importArchive(zip)
        let item = InstalledExtension(id: "x", name: "X", version: "1", bundleName: name)
        try store.save([item])
        #expect(store.load() == [item])
        store.removeBundle(named: "../\(directory.lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: directory.path))
        store.removeBundle(named: name)
        #expect(!FileManager.default.fileExists(atPath: store.bundleURL(for: item).path))
    }
}
