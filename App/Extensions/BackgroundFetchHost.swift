import BrowserKit
import WebKit

/// Answers the compat script's background requests (see BackgroundFetch and compat.js).
extension ExtensionsHost {
    func performBackgroundFetch(_ message: Any, for context: WKWebExtensionContext) async throws -> [String: Any] {
        guard let request = BackgroundFetch.Request(message: message) else { throw NativeMessaging.Failure.invalidMessage }
        // Only extensions that read cookies anyway, and only sites the user let them access. A refusal
        // tells the script to use WebKit's fetch, as if Koala weren't there.
        guard context.hasPermission(.cookies), context.hasAccess(to: request.url) else { return ["refused": true] }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = request.sendsCookies ? BackgroundFetch.cookies(await store.allCookies(), for: request.url) : []
        let (body, response) = try await BackgroundFetch.session.data(for: BackgroundFetch.urlRequest(for: request, cookies: cookies),
                                                                      delegate: RedirectRefusal())
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard body.count <= BackgroundFetch.maxBodyLength else { throw URLError(.dataLengthExceedsMaximum) }
        // Host and path only: queries and bodies carry codes and tokens.
        log.info("Background \(request.method, privacy: .public) \(request.url.host() ?? "", privacy: .public)\(request.url.path(), privacy: .public) for \(context.webExtension.displayName ?? "an extension", privacy: .public): \(response.statusCode) with \(cookies.count) cookies")
        if request.sendsCookies {
            for cookie in BackgroundFetch.cookiesSet(by: response) { await store.setCookie(cookie) }
        }
        return BackgroundFetch.reply(to: response, body: body)
    }
}

/// Hands back the redirect response itself; the compat script decides whether to follow it.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
