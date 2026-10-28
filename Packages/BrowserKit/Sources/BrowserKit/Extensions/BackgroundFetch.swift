import Foundation

/// Background requests the compat script hands to Koala (see compat.js). WebKit sends an extension's
/// background requests without the site's cookies, where Chrome sends them to sites the extension may
/// access, so sign-in checks like Okta's see a signed-out user. Koala makes these requests itself, with
/// the cookies, and returns each response without following redirects: the script follows them so it
/// can report every step to webRequest listeners, as Chrome does.
public enum BackgroundFetch {
    public struct Request: Equatable, Sendable {
        public let url: URL
        public let method: String
        /// Name and value pairs, in order; a name can repeat.
        public let headers: [[String]]
        public let body: Data?
        /// False for `credentials: "omit"`.
        public let sendsCookies: Bool

        /// Reads the message the compat script sends: `{url, method, headers: [[name, value]], body: base64?, credentials}`.
        public init?(message: Any) {
            guard let message = message as? [String: Any],
                  let text = message["url"] as? String, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil,
                  let method = message["method"] as? String, !method.isEmpty else { return nil }
            let headers = (message["headers"] as? [[String]] ?? []).filter { $0.count == 2 }
            var body: Data?
            if let encoded = message["body"] as? String {
                guard let decoded = Data(base64Encoded: encoded) else { return nil }
                body = decoded
            }
            self.url = url
            self.method = method.uppercased()
            self.headers = headers
            self.body = body
            sendsCookies = message["credentials"] as? String != "omit"
        }
    }

    /// Responses larger than this fail rather than travel back as one message.
    public static let maxBodyLength = 32 * 1024 * 1024

    /// Headers URLSession sets itself, or that only the browser may set.
    private static let reservedHeaders: Set<String> = ["host", "content-length", "connection", "cookie", "cookie2", "keep-alive", "transfer-encoding"]

    /// Cookies stay out of URLSession: Koala adds the ones from WebKit's store and saves the ones that come back.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The cookies a browser sends to `url` (RFC 6265, section 5.4), longest paths first. SameSite doesn't
    /// apply: Chrome treats an extension's requests to sites it may access as same-site.
    public static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let host = url.host()?.lowercased() else { return [] }
        let path = url.path().isEmpty ? "/" : url.path()
        let secure = url.scheme?.lowercased() == "https"
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let domainMatches = domain.hasPrefix(".")
                ? host == domain.dropFirst() || host.hasSuffix(domain)
                : host == domain
            let pathMatches = path == cookie.path
                || path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).first == "/")
            return domainMatches && pathMatches && (secure || !cookie.isSecure) && (cookie.expiresDate.map { $0 > now } ?? true)
        }
        .sorted { $0.path.count > $1.path.count }
    }

    public static func urlRequest(for request: Request, cookies: [HTTPCookie]) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpShouldHandleCookies = false
        urlRequest.httpBody = request.body
        for header in request.headers where !reservedHeaders.contains(header[0].lowercased()) {
            urlRequest.addValue(header[1], forHTTPHeaderField: header[0])
        }
        if let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] {
            urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return urlRequest
    }

    /// What the compat script gets back: `{status, headers: [[name, value]], body: base64}`.
    public static func reply(to response: HTTPURLResponse, body: Data) -> [String: Any] {
        let headers = response.allHeaderFields.compactMap { name, value -> [String]? in
            guard let name = name as? String else { return nil }
            return [name, "\(value)"]
        }
        return ["status": response.statusCode, "headers": headers.sorted { $0[0] < $1[0] }, "body": body.base64EncodedString()]
    }

    /// The cookies a response sets, as WebKit's store should save them.
    public static func cookiesSet(by response: HTTPURLResponse) -> [HTTPCookie] {
        guard let url = response.url else { return [] }
        var fields: [String: String] = [:]
        for case let (name as String, value) in response.allHeaderFields { fields[name] = "\(value)" }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    }
}
