import WebKit

@MainActor
public enum DevToolsScripts {
    public static let consoleHandler = "koalaConsole"
    public static let metricsHandler = "koalaMetrics"
    public static let networkHandler = "koalaNetwork"
    public static let world = WKContentWorld.world(name: "KoalaDevTools")

    static func source(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Missing bundled devtools script: \(name)")
        }
        return source
    }

    public static let console = source("console")
    static let metrics = source("metrics")
    public static let network = source("network")
    public static let readStorage = """
    const dump = storage => {
      const rows = [];
      for (let i = 0; i < storage.length && i < 500; i++) {
        const key = storage.key(i), value = storage.getItem(key) || '';
        rows.push({ key, value: value.slice(0, 65536), truncated: value.length > 65536 });
      }
      return rows;
    };
    return { local: dump(localStorage), session: dump(sessionStorage), document: globalThis.__koalaDocumentID };
    """

    /// Nothing here touches the page's own world. The console hook (`console`) and fetch/XHR capture
    /// (`network`) wrap page APIs, which bot checks such as Akamai's treat as tampering and answer by
    /// never letting the page load, so the dev panel injects them only while it is open.
    public static func install(on controller: WKUserContentController, handler: WKScriptMessageHandler) {
        controller.addUserScript(WKUserScript(source: metrics, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        controller.add(handler, contentWorld: .page, name: consoleHandler)
        controller.add(handler, contentWorld: world, name: metricsHandler)
        controller.add(handler, contentWorld: .page, name: networkHandler)
    }
}
