import Foundation

/// How safely a page arrived, for the address field's warning. Only the unsafe cases show anything.
public enum PageSecurity: Equatable, Sendable {
    /// HTTPS with only secure content, or plain HTTP from this Mac (a secure context).
    case secure
    /// Plain HTTP from another machine.
    case insecure
    /// HTTPS, but some of the page's content came over plain HTTP.
    case mixed
    /// HTTPS from a server whose untrusted certificate the user accepted.
    case exception
    /// Not a web page: a native page, a blank tab, an error page, or a local file.
    case none

    public init(url: URL?, hasOnlySecureContent: Bool, hasTrustException: Bool) {
        switch url?.scheme?.lowercased() {
        case "https":
            self = hasTrustException ? .exception : hasOnlySecureContent ? .secure : .mixed
        case "http":
            self = url?.isLoopback == true ? .secure : .insecure
        default:
            self = .none
        }
    }

    public var isWarning: Bool { self == .insecure || self == .mixed || self == .exception }
}
