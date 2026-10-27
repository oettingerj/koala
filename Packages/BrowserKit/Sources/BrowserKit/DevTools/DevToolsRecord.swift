import Foundation
import Observation
import WebKit

public struct ConsoleEntry: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable, CaseIterable { case log, info, warn, error, debug }

    public let id: Int
    public let level: Level
    public let text: String
    public let source: String
    public let date: Date

    /// Validates a message posted by the page-world console hook. The page can call the
    /// handler directly, so every field is checked and capped.
    static func decode(_ body: Any, id: Int, date: Date = Date()) -> ConsoleEntry? {
        guard let dict = body as? [String: Any],
              let levelName = dict["level"] as? String, let level = Level(rawValue: levelName),
              let text = dict["text"] as? String else { return nil }
        let source = dict["source"] as? String ?? ""
        return ConsoleEntry(id: id, level: level, text: String(text.prefix(4000)),
                            source: String(source.prefix(500)), date: date)
    }
}

public struct ResourceEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let url: String
    public let type: String
    /// Milliseconds since navigation start.
    public let start: Double
    public let duration: Double
    public let transferSize: Int
    /// Compressed body size; for revalidated responses this is the real payload size.
    public let encodedSize: Int
    public let status: Int

    /// How the response was delivered, as Resource Timing reports it.
    public enum Delivery: Sendable, Equatable { case network, cached, revalidated }

    public var delivery: Delivery {
        if transferSize == 0 { return .cached }
        // The Fetch spec reports a fixed 300 bytes for responses revalidated from cache (304).
        if transferSize == 300 { return .revalidated }
        return .network
    }

    /// Bytes that crossed the network for this request (headers only when revalidated).
    public var bytesTransferred: Int { delivery == .network ? transferSize : 0 }

    static func decode(_ value: Any, id: Int) -> ResourceEntry? {
        guard let dict = value as? [String: Any], let url = dict["name"] as? String else { return nil }
        func number(_ key: String) -> Double {
            let value = (dict[key] as? NSNumber)?.doubleValue ?? 0
            return value.isFinite ? max(0, value) : 0
        }
        return ResourceEntry(id: id, url: String(url.prefix(2000)),
                             type: String((dict["type"] as? String ?? "other").prefix(32)),
                             start: number("start"), duration: number("duration"),
                             transferSize: Int(number("size")), encodedSize: Int(number("encoded")),
                             status: Int(number("status")))
    }
}

public struct Vitals: Equatable, Sendable {
    public var ttfb: Double?
    public var lcp: Double?
    public var cls: Double?
    public var inp: Double?
    public var load: Double?

    public init() {}

    mutating func merge(_ value: Any?) {
        guard let dict = value as? [String: Any] else { return }
        func read(_ key: String) -> Double? {
            guard let number = (dict[key] as? NSNumber)?.doubleValue, number.isFinite, number >= 0 else { return nil }
            return number
        }
        ttfb = read("ttfb") ?? ttfb
        lcp = read("lcp") ?? lcp
        cls = read("cls") ?? cls
        inp = read("inp") ?? inp
        load = read("load") ?? load
    }
}

public struct MainResponse: Equatable, Sendable {
    public var url: URL?
    public var statusCode: Int
    public var mimeType: String?
    public var headers: [(String, String)]

    public static func == (a: MainResponse, b: MainResponse) -> Bool {
        a.url == b.url && a.statusCode == b.statusCode && a.mimeType == b.mimeType
            && a.headers.map { $0.0 + $0.1 } == b.headers.map { $0.0 + $0.1 }
    }
}

/// Everything the dev panel shows for one tab, reset on every main-frame navigation.
@MainActor
@Observable
public final class DevToolsRecord {
    public private(set) var console: [ConsoleEntry] = []
    public private(set) var errorCount = 0
    public private(set) var resources: [ResourceEntry] = []
    public private(set) var vitals = Vitals()
    public private(set) var mainResponse: MainResponse?

    @ObservationIgnored private var nextID = 0
    static let consoleLimit = 2000
    static let resourceLimit = 3000

    public init() {}

    func reset() {
        console.removeAll()
        resources.removeAll()
        errorCount = 0
        vitals = Vitals()
    }

    public func clearConsole() {
        console.removeAll()
        errorCount = 0
    }

    func record(response: URLResponse) {
        let http = response as? HTTPURLResponse
        let headers = (http?.allHeaderFields ?? [:])
            .compactMap { key, value in (key as? String).map { ($0, "\(value)") } }
            .sorted { $0.0.lowercased() < $1.0.lowercased() }
        mainResponse = MainResponse(url: response.url, statusCode: http?.statusCode ?? 0,
                                    mimeType: response.mimeType, headers: headers)
    }

    func receive(console body: Any) {
        nextID += 1
        guard let entry = ConsoleEntry.decode(body, id: nextID) else { return }
        if entry.level == .error { errorCount += 1 }
        console.append(entry)
        if console.count > Self.consoleLimit { console.removeFirst(console.count - Self.consoleLimit) }
    }

    func receive(metrics body: Any) {
        guard let dict = body as? [String: Any] else { return }
        if let list = dict["resources"] as? [Any] {
            let entries = list.prefix(300).compactMap { value -> ResourceEntry? in
                nextID += 1
                return ResourceEntry.decode(value, id: nextID)
            }
            resources.append(contentsOf: entries)
            if resources.count > Self.resourceLimit { resources.removeFirst(resources.count - Self.resourceLimit) }
        }
        vitals.merge(dict["vitals"])
    }
}

/// Routes script messages from the shared content controller to the tab whose web view sent them.
@MainActor
public final class DevToolsRouter: NSObject, WKScriptMessageHandler {
    public static let shared = DevToolsRouter()
    private var records: [ObjectIdentifier: WeakRecord] = [:]

    private struct WeakRecord { weak var record: DevToolsRecord? }

    func register(_ record: DevToolsRecord, for webView: WKWebView) {
        records[ObjectIdentifier(webView)] = WeakRecord(record: record)
        records = records.filter { $0.value.record != nil }
    }

    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let webView = message.webView,
              let record = records[ObjectIdentifier(webView)]?.record else { return }
        switch message.name {
        case DevToolsScripts.consoleHandler: record.receive(console: message.body)
        case DevToolsScripts.metricsHandler: record.receive(metrics: message.body)
        default: break
        }
    }
}
