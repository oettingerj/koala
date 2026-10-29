import Foundation
import Testing
@testable import BrowserKit

@Suite struct ErrorPageTests {
    private func error(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }

    @Test func offersVisitAnywayOnlyForCertificateErrors() {
        let url = URL(string: "https://self-signed.example")!
        for code in [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid] {
            #expect(ErrorPage.isCertificateError(error(code)))
            #expect(ErrorPage.html(for: url, error: error(code)).contains(ErrorPage.proceedURL.absoluteString))
        }
        for code in [NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorSecureConnectionFailed] {
            #expect(!ErrorPage.isCertificateError(error(code)))
            #expect(!ErrorPage.html(for: url, error: error(code)).contains(ErrorPage.proceedURL.absoluteString))
        }
        #expect(!ErrorPage.isCertificateError(NSError(domain: "Other", code: NSURLErrorServerCertificateUntrusted)))
    }

    @Test func waitsOnlyForRefusedLocalServers() {
        let local = URL(string: "http://localhost:3000/app")!
        let remote = URL(string: "http://example.com")!
        #expect(ErrorPage.waitsForServer(local, error: error(NSURLErrorCannotConnectToHost)))
        #expect(ErrorPage.html(for: local, error: error(NSURLErrorCannotConnectToHost)).contains("reloads this page"))
        #expect(!ErrorPage.waitsForServer(remote, error: error(NSURLErrorCannotConnectToHost)))
        #expect(!ErrorPage.waitsForServer(local, error: error(NSURLErrorTimedOut)))
    }

    @Test func crashPageLinksBackToThePage() {
        let html = ErrorPage.crashed(URL(string: "https://example.com/a?b=1&c=2")!)
        #expect(html.contains("This page crashed"))
        #expect(html.contains("href=\"https://example.com/a?b=1&amp;c=2\""))
    }

    @Test func detectsLoopbackHosts() {
        for host in ["http://localhost:3000", "http://app.localhost", "http://127.0.0.1:8080", "http://127.1.2.3", "http://[::1]:5173"] {
            #expect(URL(string: host)!.isLoopback, "\(host)")
        }
        for host in ["http://example.com", "http://127.0.0.1.example.com", "http://192.168.1.2", "file:///tmp/x"] {
            #expect(!URL(string: host)!.isLoopback, "\(host)")
        }
    }

    @MainActor
    @Test func trustExceptionsMatchHostAndPort() {
        let exceptions = TrustExceptions()
        exceptions.insert(TrustExceptions.key(for: URL(string: "https://Dev.Example")!)!)
        #expect(exceptions.contains(host: "dev.example", port: 443))
        #expect(exceptions.contains(URL(string: "https://dev.example:443/x")))
        #expect(!exceptions.contains(host: "dev.example", port: 8443))
        #expect(TrustExceptions.key(for: URL(string: "https://localhost:8443")!) == "localhost:8443")
    }
}
