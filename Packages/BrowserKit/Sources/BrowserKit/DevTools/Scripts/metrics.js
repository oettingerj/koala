(() => {
  globalThis.__koalaDocumentID ||= String(performance.timeOrigin) + ":" + Math.random().toString(36).slice(2);
  let queue = [], vitals = {}, timer = 0;
  const flush = () => {
    timer = 0;
    try { webkit.messageHandlers.koalaMetrics.postMessage({ document: globalThis.__koalaDocumentID, resources: queue.splice(0, 300), vitals }); } catch {}
    if (queue.length) schedule();
  };
  const schedule = () => { if (!timer) timer = setTimeout(flush, 500); };
  const add = entry => {
    if (queue.length >= 3000) return;
    queue.push({ name: String(entry.name).slice(0, 2000), type: entry.initiatorType || 'other', start: entry.startTime,
      duration: entry.duration, size: entry.transferSize || 0, encoded: entry.encodedBodySize || 0, status: entry.responseStatus || 0 });
  };
  try { new PerformanceObserver(list => { list.getEntries().forEach(add); schedule(); }).observe({ type: 'resource', buffered: true }); } catch {}
  const observe = (type, callback) => {
    try { new PerformanceObserver(list => { list.getEntries().forEach(callback); schedule(); }).observe({ type, buffered: true }); } catch {}
  };
  observe('largest-contentful-paint', entry => vitals.lcp = entry.startTime);
  let sessionStart = 0, lastShift = 0, sessionValue = 0;
  observe('layout-shift', entry => {
    if (entry.hadRecentInput) return;
    if (entry.startTime - lastShift > 1000 || entry.startTime - sessionStart > 5000) { sessionStart = entry.startTime; sessionValue = 0; }
    lastShift = entry.startTime; sessionValue += entry.value;
    vitals.cls = Math.max(vitals.cls || 0, sessionValue);
  });
  // Observed maximum interaction latency, not standards-compliant INP.
  observe('event', entry => { if (entry.interactionId) vitals.inp = Math.max(vitals.inp || 0, entry.duration); });
  addEventListener('load', () => {
    const navigation = performance.getEntriesByType('navigation')[0];
    if (navigation) { vitals.ttfb = navigation.responseStart; vitals.load = navigation.loadEventStart; }
    schedule();
  });
})();
