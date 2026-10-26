import Foundation

/// The address field's resting presentation: the host in primary text, the rest quieter.
public struct DisplayURL: Equatable, Sendable {
    public var host: String
    public var remainder: String

    public init(host: String, remainder: String) {
        self.host = host
        self.remainder = remainder
    }

    public init?(_ url: URL?) {
        guard let url else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host(percentEncoded: false) else {
            self.init(host: url.absoluteString, remainder: "")
            return
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if let port = url.port { host += ":\(port)" }

        var rest = url.path(percentEncoded: false)
        if rest == "/" { rest = "" }
        if let query = url.query(percentEncoded: false) { rest += "?" + query }
        self.init(host: host, remainder: rest)
    }
}
