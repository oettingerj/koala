import Foundation
import Testing
@testable import BrowserKit

@MainActor
@Suite struct DevToolsTests {
    @Test func rejectsMalformedConsoleMessages() {
        #expect(ConsoleEntry.decode("hello", id: 1) == nil)
        #expect(ConsoleEntry.decode(["level": "shout", "text": "x"], id: 1) == nil)
        #expect(ConsoleEntry.decode(["level": "warn"], id: 1) == nil)
        let entry = ConsoleEntry.decode(["level": "error", "text": String(repeating: "a", count: 9000)], id: 1)
        #expect(entry?.text.count == 4000)
    }

    @Test func countsErrorsAndCapsHistory() {
        let record = DevToolsRecord()
        for i in 0..<(DevToolsRecord.consoleLimit + 10) {
            record.receive(console: ["level": i.isMultiple(of: 2) ? "error" : "log", "text": "\(i)"])
        }
        #expect(record.console.count == DevToolsRecord.consoleLimit)
        #expect(record.errorCount == (DevToolsRecord.consoleLimit + 10) / 2)
        record.reset()
        #expect(record.console.isEmpty && record.errorCount == 0)
    }

    @Test func decodesResourcesAndVitalsDefensively() {
        let record = DevToolsRecord()
        record.receive(metrics: [
            "resources": [
                ["name": "https://a.com/app.js", "type": "script", "start": 12.5, "duration": 30, "size": 1024, "status": 200],
                ["type": "img"],
                ["name": "https://a.com/x.png", "duration": -5],
            ],
            "vitals": ["lcp": 840.0, "cls": 0.02, "ttfb": "fast"],
        ])
        #expect(record.resources.map(\.url) == ["https://a.com/app.js", "https://a.com/x.png"])
        #expect(record.resources.last?.duration == 0)
        #expect(record.vitals.lcp == 840)
        #expect(record.vitals.ttfb == nil)
    }

    @Test func classifiesDelivery() {
        let record = DevToolsRecord()
        record.receive(metrics: ["resources": [
            ["name": "a", "size": 0, "encoded": 500],
            ["name": "b", "size": 300, "encoded": 4000],
            ["name": "c", "size": 2048, "encoded": 1900],
            ["name": "d", "size": 300, "encoded": 0],
        ]])
        #expect(record.resources.map(\.delivery) == [.cached, .revalidated, .network, .revalidated])
        #expect(record.resources.map(\.bytesTransferred) == [0, 300, 2048, 300])
    }

    @Test func distinguishesWithheldDataAndBoundsNumbers() {
        let resource = ResourceEntry.decode(["name": "https://a.test/x", "size": Double.greatestFiniteMagnitude,
                                             "encoded": Double.infinity, "duration": Double.nan], id: 1)
        #expect(resource?.transferSize == 1_000_000_000_000)
        #expect(resource?.duration == 0)
        #expect(ResourceEntry.decode(["name": "x"], id: 1)?.delivery == .unknown)
        #expect(NetworkRequest.decode(["id": "x", "url": "file:///private/test"]) == nil)
        #expect(NetworkRequest.decode(["id": "x", "url": "https://a.test", "status": 1e20])?.status == nil)
        let combining = "a" + String(repeating: "\u{301}", count: 100_000)
        #expect(DebugValue.text(combining, limit: 100).utf8.count <= 100)
        #expect(!DebugValue.text(combining, limit: 100).contains("\u{fffd}"))
    }

    @Test func rejectsOldDocumentsAndOldCaptureTokens() {
        let record = DevToolsRecord()
        record.bindDocument("page-token", isolated: "isolated-token")
        record.route(name: DevToolsScripts.consoleHandler, body: ["document": "page-token", "level": "log", "text": "real timestamp"])
        #expect(record.console.last?.text == "real timestamp")
        record.clearConsole()
        record.willNavigate()
        record.route(name: DevToolsScripts.consoleHandler, body: ["document": "10", "level": "log", "text": "new"])
        record.route(name: DevToolsScripts.consoleHandler, body: ["document": "9", "level": "log", "text": "old"])
        record.bindDocument("10", isolated: "10")
        #expect(record.console.map(\.text) == ["new"])
        let old = record.beginCapture(origin: "https://a.test")
        let token = record.beginCapture(origin: "https://a.test")
        func request(_ token: String, _ status: Int) -> [String: Any] {
            ["document": "10", "token": token, "id": "1", "url": "https://a.test/a", "status": status]
        }
        record.route(name: DevToolsScripts.networkHandler, body: request(old, 500))
        #expect(record.requests.isEmpty)
        record.route(name: DevToolsScripts.networkHandler, body: request(token, 200))
        record.route(name: DevToolsScripts.networkHandler, body: request(token, 201))
        #expect(record.requests.count == 1 && record.requests[0].status == 201)
        record.endCapture()
        record.route(name: DevToolsScripts.networkHandler, body: request(token, 500))
        #expect(record.requests[0].status == 201)
        let generation = record.navigationID
        record.willNavigate()
        #expect(record.navigationID != generation && record.document == nil)
        record.bindDocument("11", isolated: "11")
        record.route(name: DevToolsScripts.consoleHandler, body: ["document": "10", "level": "error", "text": "late"])
        #expect(record.console.count == 1)
    }

    @Test func preservesOnlyWhenRequestedAndClearsSelection() {
        let record = DevToolsRecord()
        record.bindDocument("10", isolated: "10")
        let token = record.beginPicking()
        record.route(name: DevToolsScripts.elementHandler, body: ["document": "10", "token": token, "tag": "button", "width": 120])
        #expect(record.element?.tag == "button" && !record.isPicking)
        record.appendEvaluation("command", kind: "command")
        record.preserveLog = true
        record.reset()
        #expect(record.console.count == 1 && record.element == nil)
        record.preserveLog = false
        record.reset()
        #expect(record.console.isEmpty)
    }

    @Test func capsPayloadBudgetAndShellQuotesCurl() throws {
        let record = DevToolsRecord(), token = record.beginCapture(origin: "https://a.test")
        let text = String(repeating: "x", count: 90_000)
        for index in 0..<100 {
            record.receive(network: ["token": token, "id": "\(index)", "url": "https://a.test/?q='hi'", "method": "POST",
                                     "requestBody": ["text": text], "responseBody": ["text": text]])
        }
        #expect(record.requests.count == 100)
        #expect(record.requests.reduce(0) { $0 + $1.requestBody.text.utf8.count + $1.responseBody.text.utf8.count } <= DevToolsRecord.payloadBudget)
        #expect(record.requests.first?.responseBody.note.contains("evicted") == true)
        let request = try #require(NetworkRequest.decode(["id": "x", "url": "https://a.test/?x='", "method": "POST", "requestBody": ["text": "$(nope)`test`'x"]]))
        #expect(request.curl.contains("'\\''"))
        #expect(request.curl.contains("$(nope)`test`"))
        #expect(request.requestBody.text == "$(nope)`test`'x")
    }
}
