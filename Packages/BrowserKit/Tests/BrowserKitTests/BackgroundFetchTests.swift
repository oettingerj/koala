import Foundation
import Testing
@testable import BrowserKit

@Suite struct BackgroundFetchTests {
    private func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false, expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "v", .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    @Test func matchesCookiesLikeABrowser() {
        let now = Date()
        let all = [
            cookie("sid", domain: ".okta.com"),
            cookie("host", domain: "org.okta.com", path: "/oauth2", secure: true),
            cookie("other", domain: "evil.com"),
            cookie("sibling", domain: "other.okta.com"),
            cookie("prefix", domain: "org.okta.com", path: "/oauth"),
            cookie("old", domain: "org.okta.com", expires: now.addingTimeInterval(-60)),
        ]
        let url = URL(string: "https://org.okta.com/oauth2/v1/authorize?x=1")!
        #expect(BackgroundFetch.cookies(all, for: url, now: now).map(\.name) == ["host", "sid"])
        // Secure cookies stay off plain HTTP.
        #expect(BackgroundFetch.cookies(all, for: URL(string: "http://org.okta.com/oauth2/x")!, now: now).map(\.name) == ["sid"])
    }

    @Test func readsMessagesAndBuildsRequests() throws {
        let message: [String: Any] = ["url": "https://org.okta.com/token", "method": "post", "credentials": "same-origin",
                                      "headers": [["content-type", "application/x-www-form-urlencoded"], ["host", "evil"], ["bad"]],
                                      "body": Data("a=1".utf8).base64EncodedString()]
        let request = try #require(BackgroundFetch.Request(message: message))
        #expect(request.method == "POST" && request.sendsCookies && request.body == Data("a=1".utf8))
        let urlRequest = BackgroundFetch.urlRequest(for: request, cookies: [cookie("sid", domain: ".okta.com")])
        #expect(urlRequest.value(forHTTPHeaderField: "Cookie") == "sid=v")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(urlRequest.value(forHTTPHeaderField: "Host") == nil)

        #expect(BackgroundFetch.Request(message: ["url": "file:///etc/passwd", "method": "GET"]) == nil)
        #expect(BackgroundFetch.Request(message: ["url": "https://x.com", "method": "GET", "body": "%%"]) == nil)
        #expect(BackgroundFetch.Request(message: ["url": "https://x.com", "method": "GET", "credentials": "omit"])?.sendsCookies == false)
    }

    @Test func repliesWithStatusHeadersAndBody() throws {
        let url = URL(string: "https://org.okta.com/a")!
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                                    headerFields: ["Location": "https://org.okta.com/b", "Set-Cookie": "sid=new; Path=/"]))
        let reply = BackgroundFetch.reply(to: response, body: Data("hi".utf8))
        #expect(reply["status"] as? Int == 302 && reply["body"] as? String == Data("hi".utf8).base64EncodedString())
        #expect((reply["headers"] as? [[String]])?.contains(["Location", "https://org.okta.com/b"]) == true)
        #expect(BackgroundFetch.cookiesSet(by: response).map(\.name) == ["sid"])
    }
}
