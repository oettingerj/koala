import Foundation

/// Chrome's native messaging: an extension talks to a program on the Mac (a "host") registered by a
/// JSON manifest in Chrome's NativeMessagingHosts folders. Each message is UTF-8 JSON preceded by its
/// length as a 32-bit integer in native (little-endian) byte order, over the host's stdin and stdout.
public enum NativeMessaging {
    public enum Failure: Error, Equatable, LocalizedError {
        case hostNotFound, forbidden, hostExited, messageTooLarge, invalidMessage

        // Chrome's wording, which extensions sometimes match on.
        public var errorDescription: String? {
            switch self {
            case .hostNotFound: "Specified native messaging host not found."
            case .forbidden: "Access to the specified native messaging host is forbidden."
            case .hostExited: "Native host has exited."
            case .messageTooLarge, .invalidMessage: "Error when communicating with the native messaging host."
            }
        }
    }

    /// Chrome caps messages from a host at 1 MB.
    public static let maxIncomingLength = 1024 * 1024

    public struct HostManifest: Decodable, Equatable, Sendable {
        public let name: String
        public let path: String
        public let type: String
        public let allowedOrigins: [String]

        enum CodingKeys: String, CodingKey {
            case name, path, type
            case allowedOrigins = "allowed_origins"
        }

        /// Whether the host lets the extension Chrome knows as `chromeID` connect.
        public func allows(chromeID: String) -> Bool {
            type == "stdio" && path.hasPrefix("/") && allowedOrigins.contains(origin(of: chromeID))
        }
    }

    /// How Chrome names an extension to a host, as the host's first argument and in `allowed_origins`.
    public static func origin(of chromeID: String) -> String { "chrome-extension://\(chromeID)/" }

    /// Host names are dot-separated lowercase words, so a name can never reach outside the folders.
    public static func isValidHostName(_ name: String) -> Bool {
        name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
        }
    }

    /// The host manifest named `name` in the first of `folders` that has one.
    public static func hostManifest(named name: String, in folders: [URL]) -> HostManifest? {
        guard isValidHostName(name) else { return nil }
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")),
                  let manifest = try? JSONDecoder().decode(HostManifest.self, from: data), manifest.name == name else { continue }
            return manifest
        }
        return nil
    }

    /// Where Chrome looks for host manifests: the user's folder first, then the system one.
    public static func chromeHostFolders(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true),
         URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts", isDirectory: true)]
    }

    /// One message, framed for a host's stdin.
    public static func frame(_ message: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject([message]) else { throw Failure.invalidMessage }
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        return withUnsafeBytes(of: UInt32(json.count).littleEndian) { Data($0) } + json
    }

    /// Splits a host's stdout into messages as bytes arrive.
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        /// Messages completed by `data`, decoded from JSON.
        public mutating func append(_ data: Data) throws -> [Any] {
            buffer.append(data)
            var messages: [Any] = []
            while buffer.count >= 4 {
                let start = buffer.startIndex
                let length = Int(buffer[start]) | Int(buffer[start + 1]) << 8 | Int(buffer[start + 2]) << 16 | Int(buffer[start + 3]) << 24
                guard length <= NativeMessaging.maxIncomingLength else { throw Failure.messageTooLarge }
                guard buffer.count >= 4 + length else { break }
                let json = buffer.subdata(in: start + 4 ..< start + 4 + length)
                buffer = buffer.subdata(in: start + 4 + length ..< buffer.endIndex)
                guard let message = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else {
                    throw Failure.invalidMessage
                }
                messages.append(message)
            }
            return messages
        }
    }
}
