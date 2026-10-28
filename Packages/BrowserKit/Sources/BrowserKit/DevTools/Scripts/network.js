(() => {
  if (globalThis.__koalaNetwork) return;
  const limit = 65536;
  let token = null, sequence = 0, restore = [];
  const readers = new Set();
  const body = (text = '', note = '', mime = '') => ({ text, note, mime });
  const headers = value => {
    try {
      const pairs = value instanceof Headers ? Array.from(value.entries()) : Array.isArray(value) ? value :
        value && typeof value === 'object' ? Object.entries(Object.getOwnPropertyDescriptors(value)).filter(([, d]) => 'value' in d && typeof d.value === 'string').map(([k, d]) => [k, d.value]) : [];
      return pairs.slice(0, 100).filter(pair => Array.isArray(pair) && typeof pair[0] === 'string' && typeof pair[1] === 'string').map(([k, v]) => [k.slice(0, 256), v.slice(0, 4000)]);
    }
    catch { return []; }
  };
  const textual = mime => /^(text\/|application\/(.*\+)?(json|xml)|application\/(javascript|x-www-form-urlencoded))/.test(mime.toLowerCase()) && !mime.includes('event-stream');
  const bounded = (text, mime = '') => {
    const bytes = new TextEncoder().encode(text.slice(0, limit + 1));
    return body(new TextDecoder().decode(bytes.subarray(0, limit)), bytes.length > limit || text.length > limit ? 'Truncated at 64 KiB.' : '', mime);
  };
  const requestBody = value => {
    if (value == null) return body('', 'No captured request body.');
    if (typeof value === 'string') return bounded(value);
    if (value instanceof URLSearchParams) return bounded(value.toString(), 'application/x-www-form-urlencoded');
    return body('', 'Binary, form-data and streaming request bodies are not captured.');
  };
  const readResponse = async response => {
    const mime = response.headers.get('content-type') || '';
    if (!response.body) return body('', 'No response body.', mime);
    if (!textual(mime)) return body('', 'Binary, event-stream or unknown content type; body not captured.', mime);
    if (readers.size >= 16) return body('', 'Concurrent body capture limit reached.', mime);
    const reader = response.clone().body.getReader();
    readers.add(reader);
    const chunks = []; let size = 0, truncated = false;
    try {
      while (size < limit) {
        const item = await reader.read();
        if (item.done) break;
        const remaining = limit - size;
        chunks.push(item.value.slice(0, remaining)); size += Math.min(remaining, item.value.length);
        if (item.value.length >= remaining) { truncated = true; break; }
      }
    } finally { readers.delete(reader); reader.cancel().catch(() => {}); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return body(new TextDecoder().decode(bytes), truncated ? 'Truncated at 64 KiB.' : '', mime);
  };
  const emit = record => {
    if (!token || record.token !== token) return;
    try { webkit.messageHandlers.koalaNetwork.postMessage({ ...record, document: globalThis.__koalaDocumentID }); } catch {}
  };
  const entry = (url, method, kind) => ({ id: token + ':' + (++sequence), token, url, method, kind, start: performance.now(),
    requestHeaders: [], responseHeaders: [], requestBody: body('', 'Not captured.'), responseBody: body('', 'Waiting for response.') });
  const patch = (object, key, wrapper) => {
    const original = object[key], replacement = wrapper(original);
    object[key] = replacement;
    restore.push(() => { if (object[key] === replacement) object[key] = original; });
  };
  const stop = () => {
    token = null;
    for (const reader of readers) reader.cancel().catch(() => {});
    readers.clear();
    for (const undo of restore.splice(0).reverse()) { try { undo(); } catch {} }
  };
  const enable = nextToken => {
    stop(); token = nextToken;
    try {
      patch(globalThis, 'fetch', original => function (input, options) {
        const promise = original.apply(this, arguments);
        let record;
        try {
          const url = typeof input === 'string' ? new URL(input, location.href).href : input instanceof URL ? input.href : input instanceof Request ? input.url : '';
          // Avoid invoking custom option getters again after fetch read them.
          const own = key => options && Object.getOwnPropertyDescriptor(options, key)?.value;
          record = entry(url, String(own('method') || (input instanceof Request ? input.method : 'GET')).toUpperCase(), 'fetch');
          record.requestHeaders = headers(own('headers') || (input instanceof Request ? input.headers : undefined));
          record.requestBody = requestBody(own('body'));
          if (input instanceof Request && input.body && !own('body')) record.requestBody = body('', 'Request streams are not consumed for capture.');
          emit(record);
        } catch {}
        return promise.then(response => {
          if (record && record.token === token) {
            try {
              record.status = response.status; record.duration = performance.now() - record.start;
              record.responseHeaders = headers(response.headers); emit(record);
              readResponse(response).then(value => { record.responseBody = value; emit(record); }, () => {
                record.responseBody = body('', 'Response body unavailable.'); emit(record);
              });
            } catch {}
          }
          return response;
        }, error => {
          if (record) { record.error = String(error); record.duration = performance.now() - record.start;
            record.responseBody = body('', 'Request failed or was aborted.'); emit(record); }
          throw error;
        });
      });
      const state = new WeakMap();
      patch(XMLHttpRequest.prototype, 'open', original => function (method, url) {
        const result = original.apply(this, arguments);
        try { state.set(this, { method: typeof method === 'string' ? method.toUpperCase() : '?',
          url: typeof url === 'string' ? new URL(url, location.href).href : url instanceof URL ? url.href : '', headers: [] }); } catch {}
        return result;
      });
      patch(XMLHttpRequest.prototype, 'setRequestHeader', original => function (name, value) {
        const result = original.apply(this, arguments), current = state.get(this);
        if (current && current.headers.length < 100 && typeof name === 'string' && typeof value === 'string') current.headers.push([name.slice(0, 256), value.slice(0, 4000)]);
        return result;
      });
      patch(XMLHttpRequest.prototype, 'send', original => function (value) {
        const current = state.get(this);
        if (!current) return original.apply(this, arguments);
        const record = entry(current.url, current.method, 'xhr');
        record.requestHeaders = current.headers; record.requestBody = requestBody(value); emit(record);
        const failed = event => { record.error = event.type === 'abort' ? 'Aborted' : event.type === 'timeout' ? 'Timed out' : 'Network error'; };
        const done = () => {
          for (const name of ['error', 'abort', 'timeout']) this.removeEventListener(name, failed);
          try {
            record.status = this.status; record.duration = performance.now() - record.start;
            record.responseHeaders = this.getAllResponseHeaders().trim().split(/[\r\n]+/).filter(Boolean).slice(0, 100).map(line => {
              const index = line.indexOf(':'); return [line.slice(0, index), line.slice(index + 1).trim().slice(0, 4000)];
            });
            const mime = this.getResponseHeader('content-type') || '';
            if (this.responseType === 'json') record.responseBody = bounded(JSON.stringify(this.response), mime);
            else if ((!this.responseType || this.responseType === 'text') && textual(mime)) record.responseBody = bounded(this.responseText, mime);
            else record.responseBody = body('', 'Binary, streaming or unavailable response body.', mime);
          } catch { record.responseBody = body('', 'Response body unavailable.'); }
          emit(record);
        };
        for (const name of ['error', 'abort', 'timeout']) this.addEventListener(name, failed, { once: true });
        this.addEventListener('loadend', done, { once: true });
        try { return original.apply(this, arguments); }
        catch (error) { this.removeEventListener('loadend', done); for (const name of ['error', 'abort', 'timeout']) this.removeEventListener(name, failed);
          record.error = String(error); record.duration = performance.now() - record.start; emit(record); throw error; }
      });
      return true;
    } catch { stop(); return false; }
  };
  Object.defineProperty(globalThis, '__koalaNetwork', { value: { enable, stop }, configurable: true });
})();
