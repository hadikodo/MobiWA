// Runs only on https://app.mobiwa.com (see manifest).
// Relays window messages between the MobiWA web app and the extension.
//
//   app  → window.postMessage({source:'mobiwa-app', id, method, args})
//   here → chrome.runtime.sendMessage → background.js → WhatsApp Web tab
//   here ← response / events → window.postMessage({source:'mobiwa-ext', ...})
//
// Security: only same-window, same-origin messages from app.mobiwa.com are
// relayed; method names are checked again in background.js.
(() => {
  const ALLOWED_ORIGIN = 'https://app.mobiwa.com';
  if (location.origin !== ALLOWED_ORIGIN) return;

  const METHODS = new Set([
    'status', 'openWhatsApp', 'focusApp', 'overlay', 'cancel', 'scanUnsaved', 'readChat', 'sendMessage',
  ]);

  window.addEventListener('message', (e) => {
    if (e.source !== window || e.origin !== ALLOWED_ORIGIN) return;
    const d = e.data;
    if (!d || typeof d !== 'object' || d.source !== 'mobiwa-app') return;
    if (typeof d.id !== 'string' || d.id.length > 100 || !METHODS.has(d.method)) return;
    const args = d.args && typeof d.args === 'object' ? d.args : {};

    const reply = (payload) =>
      window.postMessage({ source: 'mobiwa-ext', type: 'response', id: d.id, ...payload }, ALLOWED_ORIGIN);
    try {
      chrome.runtime.sendMessage({ kind: 'call', method: d.method, args }, (resp) => {
        const err = chrome.runtime.lastError;
        reply({
          ok: !err && !!resp && resp.ok,
          result: resp && resp.result,
          error: err ? err.message : resp && resp.error,
        });
      });
    } catch {
      // Extension was updated / reloaded: this page must be refreshed.
      reply({ ok: false, error: 'Please reload the page.' });
    }
  });

  chrome.runtime.onMessage.addListener((msg, sender) => {
    if (sender.id !== chrome.runtime.id) return;
    if (msg && msg.kind === 'event' && (msg.event === 'stop' || msg.event === 'scanProgress')) {
      window.postMessage({ source: 'mobiwa-ext', type: 'event', event: msg.event, data: msg.data }, ALLOWED_ORIGIN);
    }
  });
})();
