(() => {
  if (globalThis.__koalaElements) return;
  let token = null, selected = null, overlay = null;
  const descriptor = element => element.localName + (element.id ? '#' + element.id : '') + [...element.classList].slice(0, 2).map(c => '.' + c).join('');
  const selector = element => {
    const path = [];
    for (let node = element; node && path.length < 8; node = node.parentElement) {
      if (node.id) { path.unshift('#' + CSS.escape(node.id)); break; }
      const siblings = node.parentElement ? [...node.parentElement.children].filter(e => e.localName === node.localName) : [];
      path.unshift(node.localName + (siblings.length > 1 ? ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')' : ''));
    }
    return path.join(' > ');
  };
  const snapshot = element => {
    const box = element.getBoundingClientRect(), style = getComputedStyle(element), ancestors = [];
    for (let node = element; node && ancestors.length < 12; node = node.parentElement || node.getRootNode().host) ancestors.unshift(descriptor(node));
    const names = ['display','position','box-sizing','width','height','margin','padding','border','gap','align-items','justify-content','font-family','font-size','font-weight','line-height','color','background-color','overflow','z-index'];
    return { document: globalThis.__koalaDocumentID, token, tag: descriptor(element), selector: selector(element),
      html: element.outerHTML.slice(0, 32000), width: box.width, height: box.height, ancestors,
      styles: names.map(name => [name, style.getPropertyValue(name)]),
      attributes: [...element.attributes].filter(a => /^(id|class|role|aria-|alt$|title$|tabindex$|type$|name$)/.test(a.name)).slice(0, 60).map(a => [a.name, a.value.slice(0, 4000)]) };
  };
  const hover = event => {
    selected = event.composedPath().find(node => node instanceof Element && node !== overlay);
    if (!selected || !overlay) return;
    const box = selected.getBoundingClientRect();
    Object.assign(overlay.style, { left: box.left + 'px', top: box.top + 'px', width: box.width + 'px', height: box.height + 'px' });
  };
  const stop = () => {
    removeEventListener('pointermove', hover, true); removeEventListener('click', click, true); removeEventListener('keydown', key, true);
    overlay?.remove(); overlay = null; selected = null; token = null;
  };
  const click = event => {
    event.preventDefault(); event.stopImmediatePropagation();
    const target = event.composedPath().find(node => node instanceof Element && node !== overlay);
    overlay?.remove();
    try { webkit.messageHandlers.koalaElement.postMessage(target ? snapshot(target) : { document: globalThis.__koalaDocumentID, token }); } finally { stop(); }
  };
  const key = event => {
    if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation();
      try { webkit.messageHandlers.koalaElement.postMessage({ document: globalThis.__koalaDocumentID, token }); } finally { stop(); } }
  };
  const start = value => {
    stop(); token = value;
    overlay = document.createElement('div');
    overlay.setAttribute('aria-hidden','true');
    overlay.style.cssText = 'position:fixed!important;pointer-events:none!important;z-index:2147483647!important;outline:2px solid #0e8f80!important;background:rgba(14,143,128,.10)!important;';
    document.documentElement.append(overlay);
    addEventListener('pointermove', hover, true); addEventListener('click', click, true); addEventListener('keydown', key, true);
  };
  Object.defineProperty(globalThis, '__koalaElements', { value: { start, stop }, configurable: true });
})();
