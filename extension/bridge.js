// Runs on app.mobiwa.com (and localhost while developing).
// Relays window messages between the MobiWA web app and the extension.
//
//   app  → window.postMessage({source:'mobiwa-app', id, method, args})
//   here → chrome.runtime.sendMessage → background.js → WhatsApp Web tab
//   here ← response / events → window.postMessage({source:'mobiwa-ext', ...})
(() => {
  const origin = location.origin;

  window.addEventListener('message', (e) => {
    if (e.source !== window || !e.data || e.data.source !== 'mobiwa-app') return;
    const { id, method, args } = e.data;
    try {
      chrome.runtime.sendMessage({ kind: 'call', method, args: args || {} }, (resp) => {
        const err = chrome.runtime.lastError;
        window.postMessage(
          {
            source: 'mobiwa-ext',
            type: 'response',
            id,
            ok: !err && !!resp && resp.ok,
            result: resp && resp.result,
            error: err ? err.message : resp && resp.error,
          },
          origin,
        );
      });
    } catch (error) {
      // Extension was updated / reloaded: this page must be refreshed.
      window.postMessage(
        { source: 'mobiwa-ext', type: 'response', id, ok: false, error: 'Please reload the page.' },
        origin,
      );
    }
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg && msg.kind === 'event') {
      window.postMessage({ source: 'mobiwa-ext', type: 'event', event: msg.event, data: msg.data }, origin);
    }
  });
})();
