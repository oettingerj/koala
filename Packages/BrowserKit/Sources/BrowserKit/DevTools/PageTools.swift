import Foundation

/// Developer page tools that render inside the page: the JSON viewer and view source.
public enum PageTools {
    private static let palette = """
    :root { --bg:#FAFAFA; --fg:#18181B; --muted:#6C6C75; --rule:#DEDEE1; --key:#0E8F80; --str:#248A57;
            --num:#B07A0A; --kw:#8E4EC6; --hover:#EBEBED; }
    @media (prefers-color-scheme: dark) {
      :root { --bg:#1E1E21; --fg:#F4F4F5; --muted:#8A8A93; --rule:#303035; --key:#2CC3AE; --str:#3DD68C;
              --num:#F5A524; --kw:#B57FE8; --hover:#26262A; } }
    ::selection { background: color-mix(in srgb, var(--key) 30%, transparent); }
    """

    /// Replaces a raw JSON document with a collapsible tree, a filter, and a Raw toggle.
    /// Runs in the isolated dev tools world, so page scripts cannot interfere.
    public static let jsonViewer = """
    (() => {
      const raw = document.body ? document.body.innerText : '';
      let data; try { data = JSON.parse(raw); } catch { return false; }
      const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text; return e; };
      const render = (value, key) => {
        const row = el('div', 'row');
        if (key !== undefined) { row.append(el('span', 'key', JSON.stringify(key)), el('span', 'p', ': ')); }
        if (value && typeof value === 'object') {
          const isArray = Array.isArray(value), entries = Object.entries(value);
          const toggle = el('span', 'toggle', '▾');
          const summary = el('span', 'p', isArray ? `[${entries.length}]` : `{${entries.length}}`);
          const children = el('div', 'children');
          entries.forEach(([k, v]) => children.append(render(v, isArray ? undefined : k)));
          toggle.onclick = summary.onclick = () => { const c = children.hidden = !children.hidden; toggle.textContent = c ? '▸' : '▾'; };
          row.append(toggle, summary, children);
        } else {
          const cls = value === null ? 'kw' : typeof value === 'string' ? 'str' : typeof value === 'number' ? 'num' : 'kw';
          row.append(el('span', cls, JSON.stringify(value)));
        }
        return row;
      };
      // A constructed stylesheet: strict JSON endpoints send CSP that blocks <style> elements.
      const sheet = new CSSStyleSheet();
      sheet.replaceSync(`\(palette)
        html { background: var(--bg); color: var(--fg); font: 12px/1.6 ui-monospace, SFMono-Regular, monospace; }
        body { margin: 0; } header { position: sticky; top: 0; display: flex; gap: 8px; padding: 8px 16px;
          background: var(--bg); border-bottom: 1px solid var(--rule); font-family: -apple-system, system-ui; }
        input { flex: 1; font: 12px -apple-system, system-ui; padding: 4px 8px; border: 1px solid var(--rule);
          border-radius: 6px; background: transparent; color: var(--fg); outline: none; }
        input:focus { border-color: var(--key); }
        button { font: 12px -apple-system, system-ui; padding: 4px 10px; border: 1px solid var(--rule);
          border-radius: 6px; background: transparent; color: var(--fg); cursor: pointer; }
        button:hover { background: var(--hover); } main { padding: 12px 16px; }
        .children { padding-left: 18px; border-left: 1px solid var(--rule); margin-left: 4px; }
        .toggle { cursor: pointer; color: var(--muted); display: inline-block; width: 14px; }
        .key { color: var(--key); } .str { color: var(--str); word-break: break-all; } .num { color: var(--num); }
        .kw { color: var(--kw); } .p { color: var(--muted); cursor: default; } .hidden { display: none; }
        pre { margin: 0; white-space: pre-wrap; word-break: break-all; }`);
      document.adoptedStyleSheets = [sheet];
      const scheme = document.createElement('meta'); scheme.name = 'color-scheme'; scheme.content = 'light dark';
      document.head.append(scheme);
      const header = el('header'), filter = el('input'), rawButton = el('button', '', 'Raw'), main = el('main');
      filter.placeholder = 'Filter keys and values';
      const tree = render(data), pre = el('pre', 'hidden', JSON.stringify(data, null, 2));
      rawButton.onclick = () => { tree.classList.toggle('hidden'); pre.classList.toggle('hidden');
        rawButton.textContent = pre.classList.contains('hidden') ? 'Raw' : 'Tree'; };
      filter.oninput = () => { const q = filter.value.toLowerCase();
        tree.querySelectorAll('.row').forEach(r => { r.style.display = !q || r.textContent.toLowerCase().includes(q) ? '' : 'none'; }); };
      header.append(filter, rawButton); main.append(tree, pre);
      document.body.replaceChildren(header, main);
      return true;
    })()
    """

    /// Script that returns the live document's markup.
    public static let readSource = "document.documentElement ? document.documentElement.outerHTML : ''"

    /// A read-only source page with line numbers for `html` captured from `url`.
    public static func sourcePage(for html: String, url: URL) -> String {
        let lines = html.components(separatedBy: "\n")
        let body = lines.enumerated().map { index, line in
            "<tr><td class=\"n\">\(index + 1)</td><td class=\"l\">\(escape(line))</td></tr>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <title>Source of \(escape(url.absoluteString))</title>
        <style>\(palette)
          html { background: var(--bg); color: var(--fg); font: 12px/1.55 ui-monospace, SFMono-Regular, monospace; }
          body { margin: 0; } table { border-collapse: collapse; width: 100%; }
          .n { color: var(--muted); text-align: right; padding: 0 12px; user-select: none; width: 1%;
               border-right: 1px solid var(--rule); vertical-align: top; }
          .l { padding: 0 16px; white-space: pre-wrap; word-break: break-all; }
          header { padding: 8px 16px; border-bottom: 1px solid var(--rule); color: var(--muted);
                   font: 12px -apple-system, system-ui; position: sticky; top: 0; background: var(--bg); }
        </style></head><body><header>\(escape(url.absoluteString)) · live DOM · \(lines.count) lines</header>
        <table>\(body)</table></body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
