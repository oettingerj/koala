import Foundation

/// Untrusted page data is bounded before it becomes observable application state.
enum DebugValue {
    static func text(_ value: Any?, limit: Int = 4000) -> String {
        var bytes = Array((value as? String ?? "").utf8.prefix(max(0, limit)))
        while !bytes.isEmpty {
            if let text = String(bytes: bytes, encoding: .utf8) { return text }
            bytes.removeLast() // A UTF-8 prefix can end inside its final scalar.
        }
        return ""
    }

    static func number(_ value: Any?, maximum: Double = 1e12) -> Double? {
        guard let value = (value as? NSNumber)?.doubleValue, value.isFinite, value >= 0 else { return nil }
        return min(value, maximum)
    }

    static func headers(_ value: Any?) -> [DebugHeader] {
        var budget = 8192
        return (value as? [[String]] ?? []).prefix(100).compactMap { pair in
            guard pair.count == 2, budget > 0 else { return nil }
            let name = text(pair[0], limit: min(256, budget))
            budget -= name.utf8.count
            let value = text(pair[1], limit: max(0, min(2000, budget)))
            budget -= value.utf8.count
            return DebugHeader(name: name, value: value)
        }
    }
}

public struct DebugHeader: Equatable, Sendable {
    public let name: String
    public let value: String
}

public struct CapturedBody: Equatable, Sendable {
    public var text: String
    public var note: String
    public let mimeType: String

    static func decode(_ value: Any?) -> CapturedBody {
        let dict = value as? [String: Any] ?? [:]
        let raw = dict["text"] as? String ?? ""
        return CapturedBody(text: DebugValue.text(raw, limit: 65_536),
                            note: DebugValue.text(dict["note"], limit: 200),
                            mimeType: DebugValue.text(dict["mime"], limit: 200))
    }

    public var formattedText: String {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let result = String(data: pretty, encoding: .utf8) else { return text }
        return result
    }
}

public struct NetworkRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let method: String
    public let kind: String
    public let start: Double
    public var duration: Double?
    public var status: Int?
    public var error: String
    public var requestHeaders: [DebugHeader]
    public var responseHeaders: [DebugHeader]
    public var requestBody: CapturedBody
    public var responseBody: CapturedBody

    static func decode(_ body: Any) -> NetworkRequest? {
        guard let dict = body as? [String: Any], let id = dict["id"] as? String, !id.isEmpty,
              let url = dict["url"] as? String, let scheme = URL(string: url)?.scheme,
              ["http", "https"].contains(scheme) else { return nil }
        return NetworkRequest(id: DebugValue.text(id, limit: 120), url: DebugValue.text(url, limit: 8000),
                              method: DebugValue.text(dict["method"], limit: 32), kind: DebugValue.text(dict["kind"], limit: 16),
                              start: DebugValue.number(dict["start"]) ?? 0, duration: DebugValue.number(dict["duration"]),
                              status: DebugValue.number(dict["status"]).flatMap { $0 >= 100 && $0 <= 599 ? Int($0) : nil },
                              error: DebugValue.text(dict["error"]), requestHeaders: DebugValue.headers(dict["requestHeaders"]),
                              responseHeaders: DebugValue.headers(dict["responseHeaders"]),
                              requestBody: CapturedBody.decode(dict["requestBody"]), responseBody: CapturedBody.decode(dict["responseBody"]))
    }

    /// Captured script-visible fields only. Browser-added cookies and credentials are unavailable.
    public var curl: String {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var parts = ["curl", "--request", quote(method), "--url", quote(url)]
        for header in requestHeaders { parts += ["--header", quote(header.name + ": " + header.value)] }
        if !requestBody.text.isEmpty { parts += ["--data-raw", quote(requestBody.text)] }
        return parts.joined(separator: " ")
    }
}

public struct ElementSnapshot: Equatable, Sendable {
    public let selector: String
    public let html: String
    public let tag: String
    public let width: Double
    public let height: Double
    public let ancestors: [String]
    public let styles: [DebugHeader]
    public let attributes: [DebugHeader]

    static func decode(_ value: Any) -> ElementSnapshot? {
        guard let dict = value as? [String: Any], let tag = dict["tag"] as? String else { return nil }
        return ElementSnapshot(selector: DebugValue.text(dict["selector"], limit: 2000), html: DebugValue.text(dict["html"], limit: 32_000),
                               tag: DebugValue.text(tag, limit: 100), width: DebugValue.number(dict["width"]) ?? 0,
                               height: DebugValue.number(dict["height"]) ?? 0,
                               ancestors: (dict["ancestors"] as? [String] ?? []).prefix(12).map { DebugValue.text($0, limit: 200) },
                               styles: DebugValue.headers(dict["styles"]), attributes: DebugValue.headers(dict["attributes"]))
    }
}
