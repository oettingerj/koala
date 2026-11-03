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
    public var arguments: [String] = []
    public var stack: String = ""
    public var kind: String = "message"

    /// Validates a message posted by the page-world console hook. The page can call the
    /// handler directly, so every field is checked and capped.
    static func decode(_ body: Any, id: Int, date: Date = Date()) -> ConsoleEntry? {
        guard let dict = body as? [String: Any],
              let levelName = dict["level"] as? String, let level = Level(rawValue: levelName),
              let text = dict["text"] as? String else { return nil }
        let source = dict["source"] as? String ?? ""
        var entry = ConsoleEntry(id: id, level: level, text: DebugValue.text(text),
                                 source: DebugValue.text(source, limit: 500), date: date)
        entry.arguments = (dict["arguments"] as? [String] ?? []).prefix(12).map { DebugValue.text($0) }
        entry.stack = DebugValue.text(dict["stack"], limit: 8000)
        return entry
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
    public enum Delivery: Sendable, Equatable { case network, cached, revalidated, unknown }

    public var delivery: Delivery {
        if transferSize == 0 { return encodedSize > 0 ? .cached : .unknown }
        // The Fetch spec reports a fixed 300 bytes for responses revalidated from cache (304).
        if transferSize == 300 { return .revalidated }
        return .network
    }

    /// Bytes that crossed the network for this request (headers only when revalidated).
    public var bytesTransferred: Int { transferSize }

    static func decode(_ value: Any, id: Int) -> ResourceEntry? {
        guard let dict = value as? [String: Any], let url = dict["name"] as? String else { return nil }
        func number(_ key: String) -> Double {
            let value = (dict[key] as? NSNumber)?.doubleValue ?? 0
            return value.isFinite ? min(1e12, max(0, value)) : 0
        }
        return ResourceEntry(id: id, url: DebugValue.text(url, limit: 2000),
                             type: DebugValue.text(dict["type"] as? String ?? "other", limit: 32),
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
    public private(set) var requests: [NetworkRequest] = []
    public var preserveLog = false
    public private(set) var navigationID = UUID()
    public private(set) var captureID: String?
    public private(set) var captureOrigin: String?
    public private(set) var document: String?
    public private(set) var isolatedDocument: String?
    @ObservationIgnored private var pendingMessages: [(String, Any)] = []
    @ObservationIgnored private var clearedRequestIDs: Set<String> = []
    static let payloadBudget = 8 * 1024 * 1024

    @ObservationIgnored private var nextID = 0
    static let consoleLimit = 2000
    static let resourceLimit = 3000

    public init() {}

    func reset() {
        navigationID = UUID()
        if !preserveLog {
            clearConsole()
            resources.removeAll()
            requests.removeAll()
        }
        vitals = Vitals()
    }

    func willNavigate() {
        navigationID = UUID()
        document = nil
        isolatedDocument = nil
        pendingMessages.removeAll()
        mainResponse = nil
    }

    /// Binds the committed document. The page world has no token until the dev panel hooks it,
    /// so `value` is nil then and `bindPageDocument` supplies it later.
    public func bindDocument(_ value: String?, isolated: String) {
        guard Self.isToken(isolated) else { return }
        isolatedDocument = isolated
        if let value, Self.isToken(value) { document = value }
        replayPending()
    }

    /// The page world's token, read once the dev panel has hooked the console.
    public func bindPageDocument(_ value: String) {
        guard Self.isToken(value) else { return }
        document = value
        replayPending()
    }

    private static func isToken(_ value: String) -> Bool { !value.isEmpty && value.count <= 120 }

    private func replayPending() {
        let pending = pendingMessages
        pendingMessages.removeAll()
        for (name, body) in pending { route(name: name, body: body) }
    }

    func route(name: String, body: Any) {
        guard let dict = body as? [String: Any], let stamp = dict["document"] as? String, stamp.count <= 120 else { return }
        guard let expected = name == DevToolsScripts.consoleHandler || name == DevToolsScripts.networkHandler ? document : isolatedDocument else {
            if pendingMessages.count < 64 { pendingMessages.append((name, body)) }
            return
        }
        guard stamp == expected else { return }
        switch name {
        case DevToolsScripts.consoleHandler: receive(console: body)
        case DevToolsScripts.metricsHandler: receive(metrics: body)
        case DevToolsScripts.networkHandler: receive(network: body)
        default: break
        }
    }

    public func beginCapture(origin: String) -> String {
        let token = UUID().uuidString
        captureID = token
        captureOrigin = origin
        return token
    }

    public func endCapture() { captureID = nil; captureOrigin = nil }
    public func clearNetwork() {
        resources.removeAll()
        // Rotate the capture token in the model when clearing, rejecting late body updates.
        requests.removeAll()
        clearedRequestIDs.removeAll()
    }

    public func appendEvaluation(_ text: String, level: ConsoleEntry.Level = .log, kind: String) {
        nextID += 1
        var entry = ConsoleEntry(id: nextID, level: level, text: DebugValue.text(text, limit: 16_000), source: "", date: Date())
        entry.kind = kind
        append([entry])
    }

    func receive(network body: Any) {
        guard let dict = body as? [String: Any], let token = captureID, dict["token"] as? String == token,
              let entry = NetworkRequest.decode(body), !clearedRequestIDs.contains(entry.id) else { return }
        if let index = requests.firstIndex(where: { $0.id == entry.id }) {
            // Payload updates may arrive after response completion. Scripts send complete snapshots.
            requests[index] = entry
        } else {
            if requests.count >= Self.resourceLimit {
                clearedRequestIDs.insert(requests.removeFirst().id)
                if clearedRequestIDs.count > Self.resourceLimit { clearedRequestIDs.removeAll() }
            }
            requests.append(entry)
        }
        var total = requests.reduce(0) { $0 + $1.requestBody.text.utf8.count + $1.responseBody.text.utf8.count }
        for index in requests.indices where total > Self.payloadBudget {
            total -= requests[index].requestBody.text.utf8.count + requests[index].responseBody.text.utf8.count
            requests[index].requestBody.text = ""
            requests[index].responseBody.text = ""
            requests[index].requestBody.note = "Payload evicted to keep capture within 8 MiB."
            requests[index].responseBody.note = "Payload evicted to keep capture within 8 MiB."
        }
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

    /// The console hook posts batches: `{document, entries: [message]}`.
    func receive(console body: Any) {
        guard let list = (body as? [String: Any])?["entries"] as? [Any] else { return }
        append(list.prefix(Self.consoleLimit).compactMap { value -> ConsoleEntry? in
            nextID += 1
            return ConsoleEntry.decode(value, id: nextID)
        })
    }

    private func append(_ entries: [ConsoleEntry]) {
        guard !entries.isEmpty else { return }
        let errors = entries.count { $0.level == .error }
        if errors > 0 { errorCount += errors }
        console.append(contentsOf: entries)
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
        record.route(name: message.name, body: message.body)
    }
}
