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
}
