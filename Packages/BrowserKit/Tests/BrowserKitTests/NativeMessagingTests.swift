import Foundation
import Testing
@testable import BrowserKit

@Suite struct NativeMessagingTests {
    @Test func framesWithLittleEndianLength() throws {
        let data = try NativeMessaging.frame(["a": 1])
        #expect(data.prefix(4) == Data([7, 0, 0, 0]))
        #expect(String(decoding: data.dropFirst(4), as: UTF8.self) == #"{"a":1}"#)
        #expect(throws: NativeMessaging.Failure.invalidMessage) { try NativeMessaging.frame(Date()) }
    }

    @Test func readsMessagesSplitAcrossChunks() throws {
        let stream = try NativeMessaging.frame(["first": true]) + NativeMessaging.frame("second")
        var reader = NativeMessaging.Reader()
        #expect(try reader.append(stream.prefix(3)).isEmpty)
        let first = try reader.append(stream.dropFirst(3).prefix(17))
        #expect((first.first as? [String: Bool]) == ["first": true])
        #expect(try reader.append(stream.dropFirst(20)).first as? String == "second")
    }

    @Test func refusesOversizedAndBrokenMessages() {
        var reader = NativeMessaging.Reader()
        let huge = withUnsafeBytes(of: UInt32(NativeMessaging.maxIncomingLength + 1).littleEndian) { Data($0) }
        #expect(throws: NativeMessaging.Failure.messageTooLarge) { try reader.append(huge) }
        var broken = NativeMessaging.Reader()
        #expect(throws: NativeMessaging.Failure.invalidMessage) { try broken.append(Data([2, 0, 0, 0]) + Data("{x".utf8)) }
    }

    @Test func findsHostsOnlyForAllowedExtensions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hosts-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"name":"com.example.host","path":"/usr/bin/true","type":"stdio","allowed_origins":["chrome-extension://abc/"]}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("com.example.host.json"))
        let host = try #require(NativeMessaging.hostManifest(named: "com.example.host", in: [folder]))
        #expect(host.allows(chromeID: "abc"))
        #expect(!host.allows(chromeID: "xyz"))
        #expect(NativeMessaging.hostManifest(named: "../com.example.host", in: [folder]) == nil)
        #expect(NativeMessaging.hostManifest(named: "com.example.missing", in: [folder]) == nil)
        #expect(!NativeMessaging.isValidHostName("Com.Example"))
        #expect(!NativeMessaging.isValidHostName("com..example"))
    }
}
