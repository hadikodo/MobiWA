// MobiWA Connector — service worker.
// Receives calls from the web app (via bridge.js) and drives the WhatsApp Web
// tab (via whatsapp.js). Mirrors the Android accessibility service:
//   status · openWhatsApp · focusApp · overlay · cancel · scanUnsaved · readChat · sendMessage

const WA_URL = 'https://web.whatsapp.com/';
let appTabId = null;
let cancelled = false;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg) return false;

  // From the web app (bridge.js).
  if (msg.kind === 'call') {
    if (sender.tab && sender.tab.id != null) appTabId = sender.tab.id;
    handle(msg.method, msg.args || {})
      .then((result) => sendResponse({ ok: true, result }))
      .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
    return true; // async response
  }

  // From WhatsApp Web (whatsapp.js): STOP pressed / scan progress.
  if (msg.kind === 'wa-event') {
    if (msg.event === 'stop') cancelled = true;
    toApp(msg.event, msg.data);
  }
  return false;
});

function toApp(event, data) {
  if (appTabId == null) return;
  chrome.tabs.sendMessage(appTabId, { kind: 'event', event, data }).catch(() => {});
}

async function handle(method, args) {
  switch (method) {
    case 'status':
      return { extension: chrome.runtime.getManifest().version, whatsapp: await waState() };

    case 'openWhatsApp': {
      const tab = await getWaTab(true);
      await focusTab(tab.id);
      return true;
    }

    case 'focusApp':
      if (appTabId != null) await focusTab(appTabId).catch(() => {});
      return true;

    case 'overlay': {
      if (args.start) cancelled = false; // a new run begins
      const tab = await getWaTab(false);
      if (tab) await askWa(tab.id, { cmd: 'overlay', text: args.text, hide: !!args.hide }, 3000).catch(() => {});
      return true;
    }

    case 'cancel': {
      cancelled = true;
      const tab = await getWaTab(false);
      if (tab) await askWa(tab.id, { cmd: 'cancel' }, 3000).catch(() => {});
      return true;
    }

    case 'scanUnsaved': {
      const tab = await readyWaTab(WA_URL, false);
      return await askWa(tab.id, { cmd: 'scan' }, 20 * 60 * 1000);
    }

    case 'readChat': {
      if (cancelled) return { status: 'cancelled', messages: [] };
      const digits = String(args.phone || '').replace(/\D/g, '');
      const tab = await readyWaTab(`${WA_URL}send?phone=${digits}`, true);
      return await askWa(tab.id, { cmd: 'readChat' }, 80 * 1000);
    }

    case 'sendMessage': {
      if (cancelled) return 'cancelled';
      const digits = String(args.phone || '').replace(/\D/g, '');
      const text = String(args.text || '');
      const media = args.media || null;
      // Text-only messages are pre-filled through the URL; media is pasted later.
      const url = media
        ? `${WA_URL}send?phone=${digits}`
        : `${WA_URL}send?phone=${digits}&text=${encodeURIComponent(text)}`;
      const tab = await readyWaTab(url, true);
      return await askWa(tab.id, { cmd: 'send', text, media }, 110 * 1000);
    }

    default:
      throw new Error(`Unknown method: ${method}`);
  }
}

// ---------------------------------------------------------------- helpers

async function getWaTab(create) {
  const tabs = await chrome.tabs.query({ url: 'https://web.whatsapp.com/*' });
  if (tabs.length) return tabs[0];
  if (!create) return null;
  return chrome.tabs.create({ url: WA_URL, active: false });
}

async function focusTab(tabId) {
  const tab = await chrome.tabs.update(tabId, { active: true });
  if (tab && tab.windowId != null) await chrome.windows.update(tab.windowId, { focused: true });
}

/** "ready" (logged in), "login" (QR code), "loading" or "closed". */
async function waState() {
  const tab = await getWaTab(false);
  if (!tab) return 'closed';
  try {
    return await askWa(tab.id, { cmd: 'state' }, 1500);
  } catch {
    return 'loading';
  }
}

/** Sends a command to whatsapp.js in the tab and waits for its answer. */
function askWa(tabId, message, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), timeoutMs);
    chrome.tabs.sendMessage(tabId, message, (resp) => {
      clearTimeout(timer);
      const err = chrome.runtime.lastError;
      if (err) return reject(new Error(err.message));
      if (!resp) return reject(new Error('No answer from WhatsApp Web'));
      if (resp.ok) resolve(resp.result);
      else reject(new Error(resp.error || 'WhatsApp Web error'));
    });
  });
}

/**
 * Brings the WhatsApp Web tab to the front, optionally navigates it (a
 * /send?phone= link opens that chat), and waits until WhatsApp Web is ready.
 */
async function readyWaTab(url, navigate) {
  let tab = await getWaTab(false);
  if (!tab) {
    tab = await chrome.tabs.create({ url, active: true });
  } else {
    await focusTab(tab.id);
    if (navigate) await chrome.tabs.update(tab.id, { url });
  }
  await focusTab(tab.id);
  if (navigate) await sleep(1200); // let the old page unload first

  for (let i = 0; i < 90; i++) {
    if (cancelled) throw new Error('cancelled');
    let state = 'loading';
    try {
      state = await askWa(tab.id, { cmd: 'state' }, 1500);
    } catch {}
    if (state === 'ready') return tab;
    if (state === 'login') throw new Error('WhatsApp Web is not linked. Scan the QR code first.');
    await sleep(700);
  }
  throw new Error('WhatsApp Web did not load in time.');
}
