import AppKit
import Testing
import WebKit
@testable import BrowserKit

/// Runs the shipped scripts in WebKit, not a reimplementation of the instrumentation.
@MainActor @Suite(.serialized) struct DevToolsScriptTests {
    @MainActor private final class Page: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let webView: WKWebView
        var messages: [(String, [String: Any])] = []
        var loaded: CheckedContinuation<Void, any Error>?
        override init() {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
            super.init()
            webView.navigationDelegate = self
            DevToolsScripts.install(on: config.userContentController, handler: self)
        }
        func load() async throws {
            try await withCheckedThrowingContinuation { continuation in
                loaded = continuation
                webView.loadHTMLString("<html><body><button id='checkout' aria-label='Complete order'>Checkout</button></body></html>", baseURL: URL(string: "https://fixture.koala.test"))
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { loaded?.resume(throwing: error); loaded = nil }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? [String: Any] { messages.append((message.name, value)) }
        }
        func js(_ source: String, world: WKContentWorld = .page) async throws -> Any? {
            try await webView.callAsyncJavaScript(source, contentWorld: world)
        }
        func dispose() {
            webView.stopLoading()
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
        }
    }

    @Test(.timeLimit(.minutes(1))) func bindsBothWorldsWithStableDocumentTokens() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load()
        let pageToken = try #require(try await page.js("return globalThis.__koalaDocumentID;") as? String)
        let isolatedToken = try #require(try await page.js("return globalThis.__koalaDocumentID;", world: DevToolsScripts.world) as? String)
        #expect(pageToken != isolatedToken)
        let record = DevToolsRecord()
        record.bindDocument(pageToken, isolated: isolatedToken)
        _ = try await page.js("console.log('bound document'); return true;")
        _ = try await page.js("return true;")
        for (name, body) in page.messages { record.route(name: name, body: body) }
        #expect(record.console.last?.text == "bound document")
        _ = try await page.js("await new Promise(resolve => setTimeout(resolve, 40)); return true;")
        #expect(try await page.js("return globalThis.__koalaDocumentID;") as? String == pageToken)
    }

    @Test(.timeLimit(.minutes(1))) func consoleSnapshotsDoNotInvokeGettersAndPreserveUndefined() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load()
        _ = try await page.js(DevToolsScripts.console)
        let getterCount = try await page.js("""
        let calls = 0; const value = { count: 3 }; value.self = value;
        Object.defineProperty(value, 'danger', { enumerable: true, get() { calls++; throw new Error('getter'); } });
        console.log(undefined, value); console.error(new Error('test error'));
        return calls;
        """) as? Int
        #expect(getterCount == 0)
        // A round trip drains earlier posted messages from the same web process.
        _ = try await page.js("return true;")
        let logs = page.messages.filter { $0.0 == "koalaConsole" }.map(\.1)
        #expect(logs.count == 2)
        #expect((logs.first?["text"] as? String)?.contains("undefined") == true)
        #expect((logs.first?["text"] as? String)?.contains("[Circular]") == true)
        #expect((logs.last?["stack"] as? String)?.contains("test error") == true)
    }

    @Test(.timeLimit(.minutes(1))) func fetchPreservesResultsRejectionsStreamsAndRestoration() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load()
        _ = try await page.js("""
        globalThis.fixtureFetch = function(input, options) {
          if (input.includes('reject')) return Promise.reject(new TypeError('fixture rejection'));
          if (options?.signal?.aborted) return Promise.reject(new DOMException('Aborted', 'AbortError'));
          if (input.includes('binary')) return Promise.resolve(new Response(new Uint8Array([1,2,3]), { headers: { 'content-type': 'application/octet-stream' } }));
          return Promise.resolve(new Response(JSON.stringify({ value: 'x'.repeat(input.includes('large') ? 90000 : 8) }), { status: 201, headers: { 'content-type': 'application/json' } }));
        }; globalThis.fetch = globalThis.fixtureFetch;
        """)
        _ = try await page.js(DevToolsScripts.network + "\nreturn __koalaNetwork.enable('test');")
        let results = try await page.js("""
        const replies = await Promise.all([fetch('https://fixture.koala.test/same'), fetch('https://fixture.koala.test/same')]);
        const values = await Promise.all(replies.map(response => response.json()));
        const large = await (await fetch('https://fixture.koala.test/large')).json();
        const binary = await (await fetch('https://fixture.koala.test/binary')).arrayBuffer();
        let rejection = false, aborted = false;
        try { await fetch('https://fixture.koala.test/reject'); } catch(error) { rejection = error.message === 'fixture rejection'; }
        const controller = new AbortController(); controller.abort();
        try { await fetch('https://fixture.koala.test/abort', { signal: controller.signal }); } catch(error) { aborted = error.name === 'AbortError'; }
        await new Promise(resolve => setTimeout(resolve, 80));
        __koalaNetwork.stop();
        return { values: values.length, large: large.value.length, binary: binary.byteLength, rejection, aborted, restored: fetch === fixtureFetch };
        """) as? [String: Any]
        #expect(results?["values"] as? Int == 2)
        #expect(results?["large"] as? Int == 90000)
        #expect(results?["binary"] as? Int == 3)
        #expect(results?["rejection"] as? Bool == true)
        #expect(results?["aborted"] as? Bool == true)
        #expect(results?["restored"] as? Bool == true)
        let requests = page.messages.filter { $0.0 == "koalaNetwork" }.map(\.1)
        let large = try #require(requests.last { ($0["url"] as? String)?.contains("large") == true })
        let captured = try #require(large["responseBody"] as? [String: Any])
        #expect((captured["text"] as? String)?.utf8.count == 65536)
        #expect((captured["note"] as? String)?.contains("Truncated") == true)
        let same = requests.filter { ($0["url"] as? String)?.contains("same") == true }
        #expect(Set(same.compactMap { $0["id"] as? String }).count == 2)
        let binary = requests.last { ($0["url"] as? String)?.contains("binary") == true }?["responseBody"] as? [String: Any]
        #expect(binary?["text"] as? String == "")
    }

    @Test(.timeLimit(.minutes(1))) func xhrAndElementPickerRetainNativeBehaviorAndCleanUp() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load()
        _ = try await page.js(DevToolsScripts.network + "\n__koalaNetwork.enable('xhr');")
        let response = try await page.js("""
        return await new Promise((resolve, reject) => {
          const request = new XMLHttpRequest();
          request.open('GET', 'data:application/json,%7B%22ok%22%3Atrue%7D');
          request.onload = () => resolve(JSON.parse(request.responseText).ok);
          request.onerror = reject; request.send();
        });
        """) as? Bool
        #expect(response == true)
        _ = try await page.js("return true;")
        #expect(page.messages.contains { $0.0 == "koalaNetwork" && $0.1["kind"] as? String == "xhr" })
        _ = try await page.js(DevToolsScripts.elements + "\n__koalaElements.start('picker');", world: DevToolsScripts.world)
        let prevented = try await page.js("""
        const target = document.querySelector('button');
        const click = new MouseEvent('click', { bubbles: true, composed: true, cancelable: true });
        target.dispatchEvent(click);
        return click.defaultPrevented;
        """) as? Bool
        #expect(prevented == true)
        _ = try await page.js("return true;")
        let element = try #require(page.messages.last { $0.0 == "koalaElement" }?.1)
        #expect(element["selector"] as? String == "#checkout")
        #expect((element["html"] as? String)?.contains("Complete order") == true)
        let clean = try await page.js("return document.querySelectorAll('div[aria-hidden]').length === 0;") as? Bool
        #expect(clean == true)
        _ = try await page.js("__koalaElements.start('again'); __koalaElements.stop();", world: DevToolsScripts.world)
    }
}
