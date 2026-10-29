import Foundation
import Observation

/// Servers whose untrusted certificates the user chose to accept from an error page.
/// Kept for this run of the app only, like Safari.
@MainActor
@Observable
public final class TrustExceptions {
    public static let shared = TrustExceptions()

    /// "host:port" for each accepted server.
    public private(set) var keys: Set<String> = []

    public init() {}

    /// The default port is spelled out so `https://example.com` and `https://example.com:443` match.
    public nonisolated static func key(host: String, port: Int?) -> String {
        "\(host.lowercased()):\(port ?? 443)"
    }

    public nonisolated static func key(for url: URL) -> String? {
        guard let host = url.host(percentEncoded: false) else { return nil }
        return key(host: host, port: url.port)
    }

    public func contains(host: String, port: Int) -> Bool {
        keys.contains(Self.key(host: host, port: port))
    }

    public func contains(_ url: URL?) -> Bool {
        url.flatMap(Self.key(for:)).map(keys.contains) ?? false
    }

    public func insert(_ key: String) { keys.insert(key) }
    public func remove(_ key: String) { keys.remove(key) }
}
