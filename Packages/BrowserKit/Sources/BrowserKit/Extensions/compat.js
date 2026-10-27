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
        if (/\.hasListeners?$/.test(path)) return false;
        const result = /\.getAll$/.test(path) ? [] : /\.get$/.test(path) ? {} : undefined;
        const callback = args.findLast(arg => typeof arg === "function");
        if (callback && !/Listener$/.test(path)) queueMicrotask(() => callback(result));
        return Promise.resolve(result);
      },
    }));
    return stubs.get(path);
  };
  const manifest = api.runtime.getManifest();
  // Only required permissions: Chrome leaves an optional permission's namespace out until it's granted,
  // and extensions check for it (Okta's `chrome.privacy` check led to a permissions call WebKit throws on).
  const permissions = (manifest.permissions ?? []).filter(name => /^[a-z][A-Za-z]*$/.test(name));
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
  // Some WebKit calls throw where Chrome answers through the promise or callback, and a throw at startup
  // stops the rest of the background script. `answer` gives the error as a result (undefined for none)
  // or throws it to reject.
  const guarded = new WeakSet();
  const answerInsteadOfThrowing = (target, key, answer) => {
    const original = target?.[key];
    if (typeof original !== "function" || guarded.has(original)) return;
    const wrapper = function (...args) {
      try { return original.apply(this, args); } catch (error) {
        const callback = args.findLast(arg => typeof arg === "function");
        let result;
        try { result = answer(error); } catch (rejection) {
          if (!callback) return Promise.reject(rejection);
          result = undefined;
        }
        if (!callback) return Promise.resolve(result);
        queueMicrotask(() => callback(result));
      }
    };
    guarded.add(wrapper);
    try { Object.defineProperty(target, key, { value: wrapper, configurable: true, writable: true }); } catch {}
  };
  // A rule WebKit can't convert (a regexFilter with `|`, say): Chrome rejects the update.
  const refuseRules = key => error => {
    console.warn("[Nano]", `declarativeNetRequest.${key} refused: ${error?.message ?? error}`);
    throw error;
  };
  // A permission WebKit doesn't know: the extension doesn't have it and can't get it.
  const notGranted = () => false;
  // WebKit reports none of an extension's own background requests to its webRequest listeners. The
  // requests Nano makes (below) report themselves, so every listener is also kept here.
  const webRequestListeners = new Map();
  const recordingEvents = new WeakSet();
  const recordWebRequestListeners = webRequest => {
    for (const name of ["onBeforeRequest", "onBeforeSendHeaders", "onSendHeaders", "onHeadersReceived", "onBeforeRedirect",
                        "onResponseStarted", "onCompleted", "onErrorOccurred"]) {
      const event = webRequest?.[name];
      if (!event || recordingEvents.has(event.addListener)) continue;
      const listeners = webRequestListeners.get(name) ?? webRequestListeners.set(name, []).get(name);
      const { addListener, removeListener } = event;
      const add = function (callback, filter, extraInfoSpec) {
        if (typeof callback === "function") listeners.push({ callback, filter: filter ?? {}, extraInfoSpec: extraInfoSpec ?? [] });
        return addListener.apply(this, arguments);
      };
      const remove = function (callback) {
        const index = listeners.findIndex(entry => entry.callback === callback);
        if (index >= 0) listeners.splice(index, 1);
        return removeListener?.apply(this, arguments);
      };
      recordingEvents.add(add);
      try {
        Object.defineProperty(event, "addListener", { value: add, configurable: true, writable: true });
        Object.defineProperty(event, "removeListener", { value: remove, configurable: true, writable: true });
      } catch {}
    }
  };
  const patch = root => {
    for (const name of permissions) fill(root, name, name);
    for (const [name, keys] of Object.entries(members)) for (const key of keys) fill(root?.[name], key, `${name}.${key}`);
    for (const key of ["updateDynamicRules", "updateSessionRules", "updateEnabledRulesets"]) answerInsteadOfThrowing(root?.declarativeNetRequest, key, refuseRules(key));
    for (const key of ["contains", "request", "remove"]) answerInsteadOfThrowing(root?.permissions, key, notGranted);
    recordWebRequestListeners(root?.webRequest);
    return root;
  };
  for (const name of ["chrome", "browser"]) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, name);
    if (!descriptor?.configurable) continue;
    const read = descriptor.get ? () => descriptor.get.call(globalThis) : () => descriptor.value;
    Object.defineProperty(globalThis, name, { get: () => patch(read()), configurable: true });
  }
  // WebKit sends an extension's background requests without the site's cookies; Chrome sends them to
  // sites the extension may access, and sign-in checks such as Okta's depend on it. For extensions that
  // read cookies (Nano gives these native messaging for this), cross-origin requests that may carry
  // credentials go to Nano, which adds the cookies, saves any the response sets, and returns redirects
  // unfollowed. This script follows them, applies the extension's own declarativeNetRequest block and
  // header rules (WebKit's don't reach requests Nano makes), and reports each step to webRequest
  // listeners the way Chrome reports a background fetch: tabId -1, type "xmlhttprequest".
  if (manifest.permissions?.includes("cookies") && typeof api.runtime.sendNativeMessage === "function" && globalThis.fetch) {
    const nativeFetch = globalThis.fetch;
    const escape = text => text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
    const toBase64 = bytes => { let text = ""; for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(text); };
    const fromBase64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));

    const matchesPattern = (pattern, url) => {
      if (pattern === "<all_urls>") return /^(https?|wss?|ftp|file|data):$/.test(url.protocol);
      const parts = /^(\*|https?|wss?|ftp|file):\/\/([^/]*)(\/.*)$/.exec(pattern);
      if (!parts) return false;
      const [, scheme, host, path] = parts;
      if (scheme === "*" ? !/^(https?|wss?):$/.test(url.protocol) : url.protocol !== `${scheme}:`) return false;
      if (host !== "*" && !(host.startsWith("*.") ? url.hostname === host.slice(2) || url.hostname.endsWith(host.slice(1)) : url.hostname === host)) return false;
      return new RegExp(`^${path.split("*").map(escape).join(".*")}$`).test(url.pathname + url.search);
    };
    const emit = (name, details) => {
      for (const { callback, filter, extraInfoSpec } of webRequestListeners.get(name) ?? []) {
        if (!(filter.urls ?? []).some(pattern => matchesPattern(pattern, new URL(details.url)))) continue;
        if (filter.types && !filter.types.includes("xmlhttprequest")) continue;
        if (filter.tabId !== undefined && filter.tabId !== -1) continue;
        if (filter.windowId !== undefined && filter.windowId !== -1) continue;
        const copy = { ...details };
        if (!extraInfoSpec.includes("requestHeaders")) delete copy.requestHeaders;
        if (!extraInfoSpec.includes("responseHeaders")) delete copy.responseHeaders;
        try { callback(copy); } catch (error) { console.error(error); }
      }
    };

    // The declarativeNetRequest conditions a background request can meet; other rules never match one.
    const inDomains = (host, domains) => domains.some(domain => host === domain || host.endsWith(`.${domain}`));
    const urlFilterPattern = (filter, caseSensitive) => {
      let source = "", rest = filter, end = "";
      if (rest.startsWith("||")) { source = "^[a-z][a-z0-9+.-]*://([^/?#]*\\.)?"; rest = rest.slice(2); }
      else if (rest.startsWith("|")) { source = "^"; rest = rest.slice(1); }
      if (rest.endsWith("|")) { end = "$"; rest = rest.slice(0, -1); }
      source += [...rest].map(c => c === "*" ? ".*" : c === "^" ? "(?:[^A-Za-z0-9_.%-]|$)" : escape(c)).join("");
      return new RegExp(source + end, caseSensitive ? "" : "i");
    };
    const ruleMatches = ({ condition = {} }, url, method) => {
      const caseSensitive = condition.isUrlFilterCaseSensitive;
      try {
        if (condition.urlFilter && !urlFilterPattern(condition.urlFilter, caseSensitive).test(url.href)) return false;
        if (condition.regexFilter && !new RegExp(condition.regexFilter, caseSensitive ? "" : "i").test(url.href)) return false;
      } catch { return false; }
      const initiator = location.hostname;
      return !(condition.resourceTypes && !condition.resourceTypes.includes("xmlhttprequest"))
        && !condition.excludedResourceTypes?.includes("xmlhttprequest")
        && !(condition.tabIds && !condition.tabIds.includes(-1)) && !condition.excludedTabIds?.includes(-1)
        && !(condition.requestMethods && !condition.requestMethods.includes(method.toLowerCase()))
        && !condition.excludedRequestMethods?.includes(method.toLowerCase())
        && !(condition.requestDomains && !inDomains(url.hostname, condition.requestDomains))
        && !(condition.excludedRequestDomains && inDomains(url.hostname, condition.excludedRequestDomains))
        && !(condition.initiatorDomains && !inDomains(initiator, condition.initiatorDomains))
        && !(condition.excludedInitiatorDomains && inDomains(initiator, condition.excludedInitiatorDomains));
    };
    const extensionRules = async () => {
      const dnr = api.declarativeNetRequest;
      if (!dnr) return [];
      const lists = await Promise.all([dnr.getSessionRules?.(), dnr.getDynamicRules?.()].map(list => Promise.resolve(list).catch(() => [])));
      return lists.flatMap(list => list ?? []);
    };
    // Highest priority wins between block and allow; header rules above an allow apply, highest first,
    // and the first rule to set or remove a header settles it.
    const applyRules = (rules, url, method, headers) => {
      const matching = rules.filter(rule => ruleMatches(rule, url, method)).sort((a, b) => (b.priority ?? 1) - (a.priority ?? 1));
      const decision = matching.find(rule => ["block", "allow", "allowAllRequests"].includes(rule.action?.type));
      if (decision?.action.type === "block") return { blocked: true, headers };
      const floor = decision ? decision.priority ?? 1 : -Infinity;
      const settled = new Set();
      let result = headers;
      for (const rule of matching) {
        if (rule.action?.type !== "modifyHeaders" || (rule.priority ?? 1) <= floor) continue;
        for (const { header, operation, value } of rule.action.requestHeaders ?? []) {
          const name = header.toLowerCase();
          if (operation === "append") { result = [...result, [name, value]]; continue; }
          if (settled.has(name)) continue;
          settled.add(name);
          result = result.filter(([existing]) => existing !== name);
          if (operation === "set") result = [...result, [name, value]];
        }
      }
      return { blocked: false, headers: result };
    };

    let nextRequestId = 1;
    const failed = () => new TypeError("Load failed");
    globalThis.fetch = async function (input, init) {
      const request = new Request(input, init);
      const url = new URL(request.url);
      if (!/^https?:$/.test(url.protocol) || url.origin === location.origin || request.credentials === "omit") return nativeFetch.call(globalThis, request);
      const fallback = request.clone();
      const requestId = `nano-${nextRequestId++}`;
      let method = request.method, current = url, hops = 0;
      let body = method === "GET" || method === "HEAD" ? null : new Uint8Array(await request.arrayBuffer());
      let headers = [...request.headers];
      if (!headers.some(([name]) => name === "user-agent")) headers.push(["user-agent", navigator.userAgent]);
      const rules = await extensionRules();
      for (;;) {
        if (request.signal.aborted) throw request.signal.reason ?? new DOMException("The operation was aborted.", "AbortError");
        const details = { requestId, url: current.href, method, frameId: -1, parentFrameId: -1, tabId: -1, type: "xmlhttprequest",
                          initiator: location.origin, timeStamp: Date.now() };
        emit("onBeforeRequest", details);
        const outcome = applyRules(rules, current, method, headers);
        if (outcome.blocked) { emit("onErrorOccurred", { ...details, error: "net::ERR_BLOCKED_BY_CLIENT" }); throw failed(); }
        headers = outcome.headers;
        const requestHeaders = headers.map(([name, value]) => ({ name, value }));
        emit("onBeforeSendHeaders", { ...details, requestHeaders });
        emit("onSendHeaders", { ...details, requestHeaders });
        let reply;
        try {
          reply = await api.runtime.sendNativeMessage("nano.fetch", { url: current.href, method, headers, body: body && toBase64(body), credentials: request.credentials });
        } catch (error) {
          emit("onErrorOccurred", { ...details, error: "net::ERR_FAILED" });
          console.warn("[Nano]", `Background request to ${current.host} failed: ${error?.message ?? error}`);
          throw failed();
        }
        // Nano declined (the extension can't access this site): WebKit's fetch, as without Nano.
        if (reply?.refused) {
          return hops === 0 ? nativeFetch.call(globalThis, fallback)
            : nativeFetch.call(globalThis, current.href, { method, headers, body, credentials: request.credentials, redirect: request.redirect, signal: request.signal });
        }
        const statusCode = reply.status, statusLine = `HTTP/1.1 ${statusCode}`;
        const responseHeaders = reply.headers.map(([name, value]) => ({ name, value }));
        emit("onHeadersReceived", { ...details, statusCode, statusLine, responseHeaders });
        const redirectTo = statusCode >= 300 && statusCode < 400 && reply.headers.find(([name]) => name.toLowerCase() === "location")?.[1];
        if (redirectTo && request.redirect !== "manual") {
          if (request.redirect === "error" || ++hops > 20) { emit("onErrorOccurred", { ...details, error: "net::ERR_TOO_MANY_REDIRECTS" }); throw failed(); }
          const next = new URL(redirectTo, current);
          emit("onBeforeRedirect", { ...details, statusCode, statusLine, responseHeaders, redirectUrl: next.href, fromCache: false });
          if (statusCode === 303 && method !== "HEAD" || (statusCode === 301 || statusCode === 302) && method === "POST") {
            method = "GET";
            body = null;
            headers = headers.filter(([name]) => !name.startsWith("content-"));
          }
          if (next.origin !== current.origin) headers = headers.filter(([name]) => name !== "authorization");
          current = next;
          continue;
        }
        emit("onResponseStarted", { ...details, statusCode, statusLine, responseHeaders, fromCache: false });
        emit("onCompleted", { ...details, statusCode, statusLine, responseHeaders, fromCache: false });
        const empty = [101, 204, 205, 304].includes(statusCode) || method === "HEAD";
        const response = new Response(empty ? null : fromBase64(reply.body), {
          status: statusCode, headers: reply.headers.filter(([name]) => name.toLowerCase() !== "set-cookie"),
        });
        Object.defineProperties(response, { url: { value: current.href }, redirected: { value: hops > 0 } });
        return response;
      }
    };
  }
  // Errors and warnings go to Nano's log (Console.app, subsystem com.joshoettinger.nano) through a
  // native host name Nano reserves. Extensions without the nativeMessaging permission skip this.
  if (manifest.permissions?.includes("nativeMessaging")) {
    const report = (level, text) => {
      try { api.runtime.sendNativeMessage("nano.console", { level, text: String(text).slice(0, 4000) }).catch(() => {}); } catch {}
    };
    const describe = value => value instanceof Error ? `${value.message}\n${value.stack ?? ""}` : typeof value === "string" ? value : (() => { try { return JSON.stringify(value); } catch { return String(value); } })();
    for (const level of ["error", "warn", "info"]) {
      const original = console[level].bind(console);
      console[level] = (...args) => { original(...args); report(level, args.map(describe).join(" ")); };
    }
    globalThis.addEventListener("error", e => report("error", `${e.message} (${e.filename}:${e.lineno})`));
    globalThis.addEventListener("unhandledrejection", e => report("error", `Unhandled rejection: ${e.reason?.name ?? ""}: ${e.reason?.message ?? e.reason} @ ${e.reason?.stack ?? ""}`));
  }
})();
