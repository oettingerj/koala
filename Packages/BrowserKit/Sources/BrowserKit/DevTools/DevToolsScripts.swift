import WebKit

/// Scripts that feed the dev panel. Console capture must run in the page's own world (that is
/// where `console` lives); timing and vitals run in an isolated world the page cannot reach.
@MainActor
public enum DevToolsScripts {
    public static let consoleHandler = "nanoConsole"
    public static let metricsHandler = "nanoMetrics"
    public static let world = WKContentWorld.world(name: "NanoDevTools")

    /// Wraps console methods and error events. Kept tiny: it runs on every page.
    static let console = """
    (() => {
      if (window.__nanoConsole) return; window.__nanoConsole = true;
      const post = (level, args, source) => {
        try {
          const text = args.map(a => {
            if (typeof a === 'string') return a;
            if (a instanceof Error) return a.stack || String(a);
            try { return JSON.stringify(a, null, 0); } catch { return String(a); }
          }).join(' ').slice(0, 4000);
          window.webkit.messageHandlers.\(consoleHandler).postMessage({ level, text, source: source || '' });
        } catch {}
      };
      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const original = console[level];
        console[level] = function (...args) { post(level, args); return original.apply(this, args); };
      }
      addEventListener('error', e => post('error', [e.message || String(e.error)],
        e.filename ? `${e.filename}:${e.lineno}:${e.colno}` : ''), true);
      addEventListener('unhandledrejection', e => post('error', ['Unhandled rejection:', e.reason]));
    })();
    """

    /// Resource timing and Core Web Vitals, batched to at most one message per 500ms.
    static let metrics = """
    (() => {
      let queue = [], vitals = {}, timer = 0;
      const flush = () => {
        timer = 0;
        const resources = queue.splice(0, 300);
        window.webkit.messageHandlers.\(metricsHandler).postMessage({ resources, vitals });
      };
      const schedule = () => { if (!timer) timer = setTimeout(flush, 500); };
      const add = e => queue.push({
        name: String(e.name).slice(0, 2000), type: e.initiatorType || 'other',
        start: e.startTime, duration: e.duration,
        size: e.transferSize || 0, encoded: e.encodedBodySize || 0, status: e.responseStatus || 0
      });
      try {
        new PerformanceObserver(l => { l.getEntries().forEach(add); schedule(); })
          .observe({ type: 'resource', buffered: true });
      } catch {}
      const vital = (type, pick) => {
        try { new PerformanceObserver(l => { l.getEntries().forEach(e => pick(e)); schedule(); })
          .observe({ type, buffered: true }); } catch {}
      };
      vital('largest-contentful-paint', e => vitals.lcp = e.startTime);
      vital('layout-shift', e => { if (!e.hadRecentInput) vitals.cls = (vitals.cls || 0) + e.value; });
      vital('event', e => { if (e.interactionId) vitals.inp = Math.max(vitals.inp || 0, e.duration); });
      const nav = performance.getEntriesByType('navigation')[0];
      if (nav) vitals.ttfb = nav.responseStart;
      addEventListener('load', () => {
        const n = performance.getEntriesByType('navigation')[0];
        if (n) { vitals.ttfb = n.responseStart; vitals.load = n.loadEventStart; }
        schedule();
      });
    })();
    """

    /// Installs both scripts and their message handlers on a content controller.
    @MainActor
    public static func install(on controller: WKUserContentController, handler: WKScriptMessageHandler) {
        controller.addUserScript(WKUserScript(source: console, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .page))
        controller.addUserScript(WKUserScript(source: metrics, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: world))
        controller.add(handler, contentWorld: .page, name: consoleHandler)
        controller.add(handler, contentWorld: world, name: metricsHandler)
    }

    /// Storage snapshot, read on demand from the isolated world.
    public static let readStorage = """
    (() => {
      const dump = s => { const o = {}; try { for (let i = 0; i < s.length && i < 500; i++) {
        const k = s.key(i); o[k] = String(s.getItem(k)).slice(0, 2000); } } catch {} return o; };
      return { local: dump(localStorage), session: dump(sessionStorage) };
    })()
    """
}
