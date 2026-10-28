(() => {
  globalThis.__nanoDocumentID ||= String(performance.timeOrigin) + ":" + Math.random().toString(36).slice(2);
  if (globalThis.__nanoConsole) return;
  const clone = (value, depth = 0, seen = new WeakSet()) => {
    try {
      if (value === undefined) return 'undefined';
      if (value === null) return 'null';
      if (typeof value === 'string') return value.slice(0, 4000);
      if (typeof value === 'bigint') return String(value) + 'n';
      if (typeof value === 'function') return '[Function]';
      if (typeof value !== 'object') return typeof value === 'symbol' ? String(value) : value;
      if (value instanceof Error) return (String(value) + '\n' + (value.stack || '')).slice(0, 4000);
      if (seen.has(value)) return '[Circular]';
      if (depth >= 3) return Array.isArray(value) ? '[Array]' : '[Object]';
      seen.add(value);
      const object = Array.isArray(value) ? [] : Object.create(null);
      for (const key of Object.keys(value).slice(0, 30)) {
        const descriptor = Object.getOwnPropertyDescriptor(value, key);
        object[key] = descriptor && 'value' in descriptor ? clone(descriptor.value, depth + 1, seen) : '[Getter]';
      }
      return object;
    } catch { return '[Unserializable]'; }
  };
  const snapshot = value => {
    const copied = clone(value);
    return (typeof copied === 'string' ? copied : JSON.stringify(copied)).slice(0, 4000);
  };
  const post = (level, args, source = '') => {
    try {
      const values = args.slice(0, 12).map(value => snapshot(value));
      const error = args.find(value => value instanceof Error);
      const stack = (error ? String(error) + '\n' + (error.stack || '') : String(new Error().stack || '')).slice(0, 8000);
      const location = source || stack.split('\n').slice(3).join('\n').split('\n')[0] || '';
      webkit.messageHandlers.nanoConsole.postMessage({ document: globalThis.__nanoDocumentID,
        level, text: values.join(' ').slice(0, 4000), arguments: values, stack, source: location });
    } catch {}
  };
  Object.defineProperty(globalThis, '__nanoConsole', { value: { snapshot }, configurable: true });
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    const original = console[level];
    console[level] = function (...args) { post(level, args); return original.apply(this, args); };
  }
  addEventListener('error', event => {
    if (!event.message && !event.error) return;
    post('error', [event.error || event.message], event.filename ? `${event.filename}:${event.lineno}:${event.colno}` : '');
  }, true);
  addEventListener('unhandledrejection', event => post('error', ['Unhandled rejection:', event.reason]));
})();
