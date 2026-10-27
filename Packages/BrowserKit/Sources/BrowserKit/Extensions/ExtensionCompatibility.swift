import Foundation

/// Chrome builds of extensions call Chrome APIs WebKit doesn't implement, often unguarded at startup,
/// which stops the background script before it does anything. Nano loads a script ahead of the
/// background script that fills those gaps with inert stand-ins.
public enum ExtensionCompatibility {
    static let folder = "nano-compat"
    static let scriptPath = "/\(folder)/compat.js"
    static let wrapperPath = "\(folder)/background.js"
    /// The native host name the compat script sends console errors to; Nano logs them instead of launching anything.
    public static let consoleHost = "nano.console"

    /// Writes the script into `bundle` and points the manifest's background at it. Safe to repeat;
    /// a bundle that is already wrapped only gets the current script.
    public static func apply(toBundleAt bundle: URL) throws {
        let manifestURL = bundle.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var background = manifest["background"] as? [String: Any] else { return }
        let directory = bundle.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: directory.appendingPathComponent("compat.js"), options: .atomic)

        var changed = false
        if let worker = background["service_worker"] as? String, worker != wrapperPath {
            let original = try specifier("/" + worker.drop { $0 == "/" })
            let source = background["type"] as? String == "module"
                ? "import \(try specifier(scriptPath));\nimport \(original);\n"
                : "importScripts(\(try specifier(scriptPath)), \(original));\n"
            try Data(source.utf8).write(to: bundle.appendingPathComponent(wrapperPath), options: .atomic)
            background["service_worker"] = wrapperPath
            changed = true
        }
        if var scripts = background["scripts"] as? [String], scripts.first != scriptPath {
            scripts.insert(scriptPath, at: 0)
            background["scripts"] = scripts
            changed = true
        }
        guard changed else { return }
        manifest["background"] = background
        let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try output.write(to: manifestURL, options: .atomic)
    }

    /// A quoted JavaScript string for a script path.
    private static func specifier(_ path: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: path, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// Stand-ins accept every call: listeners never fire, `get` and `getAll` return empty results,
    /// callbacks run with those results. Only namespaces the extension asked for in its permissions are
    /// added, plus events WebKit lacks inside namespaces it has. WebKit rebuilds the `chrome` object after
    /// startup, so the gaps are filled again on every read of `chrome` or `browser`.
    static let script = """
        // Added by Nano: inert stand-ins for Chrome extension APIs WebKit doesn't implement.
        (() => {
          const api = globalThis.chrome ?? globalThis.browser;
          if (!api?.runtime?.getManifest) return;
          // WebKit runs the background service worker on the thread its WebSocket channel waits on, so
          // `new WebSocket` deadlocks the extension (a stack sample shows WorkerThreadableWebSocketChannel
          // waiting on a BinarySemaphore forever). This stand-in fails the connection asynchronously instead.
          if (typeof ServiceWorkerGlobalScope !== "undefined" && globalThis instanceof ServiceWorkerGlobalScope && globalThis.WebSocket) {
            class NanoWebSocket extends EventTarget {
              static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
              CONNECTING = 0; OPEN = 1; CLOSING = 2; CLOSED = 3;
              readyState = 0; bufferedAmount = 0; extensions = ""; protocol = ""; binaryType = "blob";
              constructor(url) {
                super();
                this.url = String(url);
                for (const name of ["open", "message", "error", "close"]) {
                  let handler = null;
                  Object.defineProperty(this, `on${name}`, {
                    get: () => handler,
                    set: value => { if (handler) this.removeEventListener(name, handler); handler = typeof value === "function" ? value : null; if (handler) this.addEventListener(name, handler); },
                  });
                }
                console.warn("[Nano]", `WebSocket to ${new URL(this.url).host} refused: not available in a background service worker`);
                setTimeout(() => {
                  if (this.readyState === 3) return;
                  this.readyState = 3;
                  this.dispatchEvent(new Event("error"));
                  this.dispatchEvent(typeof CloseEvent === "function" ? new CloseEvent("close", { wasClean: false, code: 1006 }) : Object.assign(new Event("close"), { wasClean: false, code: 1006, reason: "" }));
                }, 0);
              }
              send() { throw new DOMException("WebSocket is not open", "InvalidStateError"); }
              close() { this.readyState = 3; }
            }
            globalThis.WebSocket = NanoWebSocket;
          }
          const stubs = new Map();
          const inert = path => {
            if (!stubs.has(path)) stubs.set(path, new Proxy(function () {}, {
              get: (_, key) => typeof key === "string" && key !== "then" ? inert(`${path}.${key}`) : undefined,
              apply: (_, __, args) => {
                if (/\\.hasListeners?$/.test(path)) return false;
                const result = /\\.getAll$/.test(path) ? [] : /\\.get$/.test(path) ? {} : undefined;
                const callback = args.findLast(arg => typeof arg === "function");
                if (callback && !/Listener$/.test(path)) queueMicrotask(() => callback(result));
                return Promise.resolve(result);
              },
            }));
            return stubs.get(path);
          };
          const manifest = api.runtime.getManifest();
          const permissions = [...(manifest.permissions ?? []), ...(manifest.optional_permissions ?? [])]
            .filter(name => /^[a-z][A-Za-z]*$/.test(name));
          const members = {
            action: ["getUserSettings", "onUserSettingsChanged"],
            runtime: ["onRestartRequired", "onSuspend", "onSuspendCanceled", "onUpdateAvailable", "setUninstallURL"],
            storage: ["managed"],
            tabs: ["onAttached", "onDetached", "onHighlighted", "onReplaced", "onZoomChange"],
            webNavigation: ["onCreatedNavigationTarget", "onHistoryStateUpdated", "onReferenceFragmentUpdated", "onTabReplaced"],
            webRequest: ["onAuthRequired"],
            windows: ["onBoundsChanged"],
          };
          const fill = (target, key, path) => {
            if (target && target[key] === undefined) {
              try { Object.defineProperty(target, key, { value: inert(path), configurable: true, writable: true }); } catch {}
            }
          };
          const patch = root => {
            for (const name of permissions) fill(root, name, name);
            for (const [name, keys] of Object.entries(members)) for (const key of keys) fill(root?.[name], key, `${name}.${key}`);
            return root;
          };
          for (const name of ["chrome", "browser"]) {
            const descriptor = Object.getOwnPropertyDescriptor(globalThis, name);
            if (!descriptor?.configurable) continue;
            const read = descriptor.get ? () => descriptor.get.call(globalThis) : () => descriptor.value;
            Object.defineProperty(globalThis, name, { get: () => patch(read()), configurable: true });
          }
          // Errors and warnings go to Nano's log (Console.app, subsystem com.joshoettinger.nano) through a
          // native host name Nano reserves. Extensions without the nativeMessaging permission skip this.
          if (manifest.permissions?.includes("nativeMessaging")) {
            const report = (level, text) => {
              try { api.runtime.sendNativeMessage("\(consoleHost)", { level, text: String(text).slice(0, 4000) }).catch(() => {}); } catch {}
            };
            const describe = value => value instanceof Error ? `${value.message}\\n${value.stack ?? ""}` : typeof value === "string" ? value : (() => { try { return JSON.stringify(value); } catch { return String(value); } })();
            for (const level of ["error", "warn", "info"]) {
              const original = console[level].bind(console);
              console[level] = (...args) => { original(...args); report(level, args.map(describe).join(" ")); };
            }
            globalThis.addEventListener("error", e => report("error", `${e.message} (${e.filename}:${e.lineno})`));
            globalThis.addEventListener("unhandledrejection", e => report("error", `Unhandled rejection: ${e.reason?.name ?? ""}: ${e.reason?.message ?? e.reason} @ ${e.reason?.stack ?? ""}`));
          }
        })();

        """
}
