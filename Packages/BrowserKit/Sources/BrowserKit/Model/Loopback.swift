import Foundation

extension URL {
    /// The page is served from this Mac: `localhost`, a `.localhost` name, or a loopback address.
    public var isLoopback: Bool {
        guard let host = host(percentEncoded: false)?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host == "[::1]" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0] == "127" && parts.allSatisfy { UInt8($0) != nil }
    }
}
