import AppKit
import BrowserKit
import CoreFoundation
import Observation
import WebKit

struct StorageItem: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let value: String
    let truncated: Bool
}

/// A session belongs to one tab. Presentation changes never retarget an in-flight operation.
@MainActor @Observable
final class DevPanelModel {
    enum Section: String, CaseIterable, Identifiable {
        case console = "Console", network = "Network", storage = "Storage", page = "Page"
        var id: String { rawValue }
    }
    enum PageAction { case viewSource, copyScreenshot, savePDF, hardReload, clearSiteData, close, detach, redock }
    let tab: BrowserKit.Tab?
    var section: Section = .console
    var isDetached = false
    /// Showing the tools starts fetch/XHR capture; each committed navigation re-arms it while they stay open.
    var isPresented = false {
        didSet { if isPresented && !oldValue { startCapture() } }
    }
    var status: String?
    var cookies: [HTTPCookie] = []
    var localStorage: [StorageItem] = []
    var sessionStorage: [StorageItem] = []
    var storageLoading = false
    var storageError: String?
    var consoleFilter = ""
    var levels = Set(ConsoleEntry.Level.allCases)
    var selectedConsole: Int?
    var networkFilter = ""
    var selectedRequest: String?
    var selectedResource: Int?
    var networkSource = "Resources"
    var networkFailures = false
    var networkKind = "All types"
    var networkSorting = "Newest"
    var networkDetail = "Overview"
    var networkRawBody = false
    var networkFocusRequest = 0
    var storageArea = "Cookies"
    var storageFilter = ""
    var selectedStorage: String?
    var storageFocusRequest = 0
    var command = ""
    var evaluating = false
    var history: [String] = []
    var historyIndex = 0
    var awaitExpression = false
    @ObservationIgnored var perform: (PageAction) -> Void = { _ in }
    @ObservationIgnored private var storageRevision = UUID()
    @ObservationIgnored private var captureRevision = UUID()
    /// Set when the user stops capture; navigations keep it off until they resume or reopen the tools.
    @ObservationIgnored private var capturePaused = false
    @ObservationIgnored private var evaluationRevision = UUID()

    init(tab: BrowserKit.Tab? = nil) { self.tab = tab }
    var origin: String? {
        guard let url = tab?.webView?.url ?? tab?.url, let scheme = url.scheme, ["http", "https"].contains(scheme),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        if scheme == "http" && parts.port == 80 || scheme == "https" && parts.port == 443 { parts.port = nil }
        return parts.string
    }
    private func current(_ webView: WKWebView, _ navigation: UUID) -> Bool {
        tab?.webView === webView && tab?.devTools.navigationID == navigation
    }

    func close() {
        isPresented = false
        storageRevision = UUID()
        evaluationRevision = UUID(); evaluating = false
        stopCapture()
    }

    func navigationDidCommit() {
        selectedConsole = nil; selectedRequest = nil; selectedResource = nil
        evaluationRevision = UUID(); evaluating = false
        storageRevision = UUID()
        cookies = []; localStorage = []; sessionStorage = []
        guard let record = tab?.devTools else { return }
        // Each document is bound to its own origin; the previous capture token never carries over.
        if isPresented && !capturePaused && origin != nil { startCapture() }
        else if record.captureID != nil { stopCapture() }
        if section == .storage && isPresented { refreshStorage() }
    }

    func startCapture() {
        capturePaused = false
        guard let tab, let webView = tab.webView, let origin else { return }
        let token = tab.devTools.beginCapture(origin: origin), navigation = tab.devTools.navigationID
        let revision = UUID(); captureRevision = revision
        Task {
            guard current(webView, navigation), captureRevision == revision, isPresented else { return }
            do {
                let enabled = try await webView.callAsyncJavaScript("if (location.origin !== expectedOrigin) return false;\n" + DevToolsScripts.network + "\nreturn globalThis.__koalaNetwork.enable(token);",
                    arguments: ["token": token, "expectedOrigin": origin], contentWorld: .page) as? Bool ?? false
                guard current(webView, navigation), captureRevision == revision else { return }
                if !enabled { tab.devTools.endCapture(); status = "This page could not enable detailed capture." }
            } catch {
                guard current(webView, navigation), captureRevision == revision else { return }
                tab.devTools.endCapture(); status = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    func pauseCapture() {
        capturePaused = true
        stopCapture()
    }

    func stopCapture() {
        captureRevision = UUID()
        tab?.devTools.endCapture()
        tab?.webView?.evaluateJavaScript("globalThis.__koalaNetwork?.stop()", in: nil, in: .page) { _ in }
    }

    func clearNetwork() {
        guard let record = tab?.devTools else { return }
        let wasCapturing = record.captureID != nil
        record.clearNetwork(); selectedRequest = nil; selectedResource = nil
        if wasCapturing { startCapture() }
    }

    func evaluate() {
        let source = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !evaluating, let tab, let webView = tab.webView, let document = tab.devTools.document else { return }
        let navigation = tab.devTools.navigationID
        let revision = UUID(); evaluationRevision = revision
        evaluating = true; command = ""
        if history.last != source { history.append(source); if history.count > 100 { history.removeFirst() } }
        historyIndex = history.count
        tab.devTools.appendEvaluation(source, kind: "command")
        let awaits = awaitExpression
        Task {
            defer { if evaluationRevision == revision { evaluating = false } }
            guard current(webView, navigation), evaluationRevision == revision else { return }
            do {
                let result: Any?
                if awaits {
                    result = try await webView.callAsyncJavaScript("if (globalThis.__koalaDocumentID !== expectedDocument) throw new Error('The inspected document changed.'); const value = await (\n\(source)\n); return globalThis.__koalaConsole ? globalThis.__koalaConsole.snapshot(value) : String(value);", arguments: ["expectedDocument": document], contentWorld: .page)
                } else {
                    let encoded = try JSONSerialization.data(withJSONObject: document, options: [.fragmentsAllowed])
                    let literal = String(decoding: encoded, as: UTF8.self)
                    result = try await webView.evaluateJavaScript("if (globalThis.__koalaDocumentID !== \(literal)) throw new Error('The inspected document changed.');\n" + source, contentWorld: .page)
                }
                await Self.flushConsole(in: webView)
                guard current(webView, navigation), evaluationRevision == revision else { return }
                let text: String
                if awaits { text = result as? String ?? "undefined" }
                else if let value = result as? String { text = value }
                else if result is NSNull { text = "null" }
                else if let number = result as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { text = number.boolValue ? "true" : "false" }
                else if let value = result, JSONSerialization.isValidJSONObject(value),
                        let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let value = String(data: data, encoding: .utf8) { text = value }
                else { text = result.map { String(describing: $0) } ?? "undefined" }
                tab.devTools.appendEvaluation(text, kind: "result")
            } catch {
                await Self.flushConsole(in: webView)
                guard current(webView, navigation), evaluationRevision == revision else { return }
                let info = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                tab.devTools.appendEvaluation(info ?? error.localizedDescription, level: .error, kind: "result")
            }
        }
    }

    /// The page sends console messages in batches; this hands over what a command logged, so its
    /// output lands above its result.
    private static func flushConsole(in webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript("globalThis.__koalaConsole?.flush()", contentWorld: .page)
    }

    func moveHistory(_ direction: Int) {
        guard !history.isEmpty else { return }
        historyIndex = max(0, min(history.count, historyIndex + direction))
        command = historyIndex < history.count ? history[historyIndex] : ""
    }

    func stopWaitingForEvaluation() {
        guard evaluating else { return }
        evaluationRevision = UUID(); evaluating = false
        tab?.devTools.appendEvaluation("Stopped waiting for this result. JavaScript already running in the page may continue.", level: .info, kind: "result")
    }

    func refreshStorage() {
        guard let tab, let webView = tab.webView, let host = tab.url?.host else { return }
        let navigation = tab.devTools.navigationID, revision = UUID()
        storageRevision = revision; storageLoading = true; storageError = nil
        cookies = []; localStorage = []; sessionStorage = []
        Task {
            let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard current(webView, navigation), storageRevision == revision else { return }
            cookies = all.filter { cookie in
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }.sorted { ($0.name, $0.domain, $0.path) < ($1.name, $1.domain, $1.path) }
            do {
                let value = try await webView.callAsyncJavaScript(DevToolsScripts.readStorage, contentWorld: DevToolsScripts.world)
                guard current(webView, navigation), storageRevision == revision else { return }
                let dict = value as? [String: Any] ?? [:]
                func items(_ key: String) -> [StorageItem] {
                    (dict[key] as? [[String: Any]] ?? []).compactMap { row in
                        guard let key = row["key"] as? String, let value = row["value"] as? String else { return nil }
                        return StorageItem(key: key, value: value, truncated: row["truncated"] as? Bool ?? false)
                    }.sorted { $0.key < $1.key }
                }
                localStorage = items("local"); sessionStorage = items("session")
            } catch {
                guard current(webView, navigation), storageRevision == revision else { return }
                storageError = "Storage is unavailable: \(error.localizedDescription)"
            }
            storageLoading = false
        }
    }

    func writeStorage(area: String, key: String, value: String?, expected: String? = nil, creating: Bool = false, completion: @escaping (Bool) -> Void) {
        guard ["local", "session"].contains(area), let tab, let webView = tab.webView, let document = tab.devTools.isolatedDocument else { completion(false); return }
        let navigation = tab.devTools.navigationID
        Task {
            guard current(webView, navigation) else { completion(false); return }
            do {
                _ = try await webView.callAsyncJavaScript("""
                const store = area === 'local' ? localStorage : sessionStorage;
                if (globalThis.__koalaDocumentID !== expectedDocument) throw new Error('The inspected document changed.');
                if (creating && store.getItem(key) !== null) throw new Error('This key already exists. Refresh and edit its value.');
                if (!creating && expected !== store.getItem(key)) throw new Error('This value changed on the page. Refresh before editing.');
                if (remove) store.removeItem(key); else store.setItem(key, value);
                """, arguments: ["area": area, "key": key, "value": value ?? "", "remove": value == nil,
                                  "expected": expected ?? "", "creating": creating, "expectedDocument": document], contentWorld: DevToolsScripts.world)
                guard current(webView, navigation) else { completion(false); return }
                refreshStorage(); completion(true)
            } catch {
                guard current(webView, navigation) else { completion(false); return }
                storageError = "Could not update storage: \(error.localizedDescription)"; completion(false)
            }
        }
    }

    func delete(_ cookie: HTTPCookie) {
        guard let tab, let webView = tab.webView else { return }
        let navigation = tab.devTools.navigationID
        Task {
            await webView.configuration.websiteDataStore.httpCookieStore.deleteCookie(cookie)
            guard current(webView, navigation) else { return }
            refreshStorage()
        }
    }
}
