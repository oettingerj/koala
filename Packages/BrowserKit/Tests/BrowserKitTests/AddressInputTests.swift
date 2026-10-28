import Foundation
import Testing
@testable import BrowserKit

@Suite struct AddressInputTests {
    @Test(arguments: [
        ("github.com", "https://github.com"),
        ("github.com/apple/swift", "https://github.com/apple/swift"),
        ("https://example.com/a?b=c", "https://example.com/a?b=c"),
        ("localhost:3000", "http://localhost:3000"),
        ("localhost:5173/app", "http://localhost:5173/app"),
        ("127.0.0.1:8080", "http://127.0.0.1:8080"),
        ("api.dev.test", "http://api.dev.test"),
        ("about:blank", "about:blank"),
        ("koala.dev", "https://koala.dev"),
        ("koala://settings", "koala://settings"),
        ("docs.rs/tokio", "https://docs.rs/tokio"),
    ])
    func resolvesURLs(input: String, expected: String) {
        #expect(AddressInput.resolve(input)?.absoluteString == expected)
    }

    @Test(arguments: ["swift concurrency", "what is 1.5", "Package.swift", "main.cpp", "foo", "c++ lambdas"])
    func searchesEverythingElse(input: String) throws {
        let url = try #require(AddressInput.resolve(input))
        #expect(url.host() == "www.google.com")
    }

    @Test func encodesQueryReservedCharacters() {
        let url = AddressInput.resolve("a&b=c #d")
        #expect(url?.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%20%23d")
    }

    @Test func emptyIsNil() {
        #expect(AddressInput.resolve("   ") == nil)
    }
}

@Suite struct DisplayURLTests {
    @Test func stripsWWWAndKeepsPath() {
        let d = DisplayURL(URL(string: "https://www.github.com/apple/swift?tab=readme"))
        #expect(d == DisplayURL(host: "github.com", remainder: "/apple/swift?tab=readme"))
    }

    @Test func keepsPort() {
        let d = DisplayURL(URL(string: "http://localhost:3000/"))
        #expect(d == DisplayURL(host: "localhost:3000", remainder: ""))
    }
}
