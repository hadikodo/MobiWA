// MobiWA Connector — service worker.
// Receives calls from the web app (via bridge.js) and drives the WhatsApp Web
// tab (via whatsapp.js). Mirrors the Android accessibility service:
//   status · openWhatsApp · focusApp · overlay · cancel · scanUnsaved · readChat · sendMessage

const WA_URL = 'https://web.whatsapp.com/';
const APP_ORIGIN = 'https://app.mobiwa.com';
const WA_ORIGIN = 'https://web.whatsapp.com';
let appTabId = null;
let cancelled = false;
let lastSendAt = 0;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------- security

const LIMITS = {
  textChars: 4096, // WhatsApp's own limit for a message / caption
  mediaBytes: 64 * 1024 * 1024,
  minGapBetweenSendsMs: 2000, // never faster than this, whatever the app asks
};
const MEDIA_TYPES = /^(image\/(jpeg|png|webp|gif)|video\/(mp4|3gpp|quicktime)|application\/pdf)$/;

const originOf = (url) => {
  try {
    return new URL(url).origin;
  } catch {
    return '';
  }
};

/** Popup (our own page) or a tab on app.mobiwa.com — nothing else may call us. */
function trustedCaller(sender) {
  if (sender.id !== chrome.runtime.id) return false;
  if (!sender.tab) return originOf(sender.url) === `chrome-extension://${chrome.runtime.id}`;
  return originOf(sender.tab.url || sender.url) === APP_ORIGIN && sender.frameId === 0;
}

function phoneDigits(v) {
  const d = String(v || '').replace(/\D/g, '');
  if (d.length < 7 || d.length > 15) throw new Error('Invalid phone number');
  return d;
}

function cleanText(v) {
  const t = String(v || '');
  if (t.length > LIMITS.textChars) throw new Error('Message is too long');
  return t;
}

function cleanMedia(m) {
  if (!m) return null;
  if (typeof m !== 'object' || typeof m.base64 !== 'string') throw new Error('Invalid file');
  const mime = String(m.mime || '');
  if (!MEDIA_TYPES.test(mime)) throw new Error('File type not allowed');
  if ((m.base64.length * 3) / 4 > LIMITS.mediaBytes) throw new Error('File is too large');
  const name = String(m.name || 'file').replace(/[^\w.\- ]/g, '_').slice(0, 100);
  return { base64: m.base64, mime, name };
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg !== 'object') return false;

  // From the web app (bridge.js) or our popup.
  if (msg.kind === 'call') {
    if (!trustedCaller(sender)) {
      sendResponse({ ok: false, error: 'Not allowed' });
      return false;
    }
    if (sender.tab && sender.tab.id != null) appTabId = sender.tab.id;
    handle(String(msg.method), msg.args && typeof msg.args === 'object' ? msg.args : {})
      .then((result) => sendResponse({ ok: true, result }))
      .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e).slice(0, 300) }));
    return true; // async response
  }

  // From WhatsApp Web (whatsapp.js): STOP pressed / scan progress.
  if (msg.kind === 'wa-event') {
    const fromWa = sender.id === chrome.runtime.id && sender.tab && originOf(sender.tab.url) === WA_ORIGIN;
    if (!fromWa) return false;
    if (msg.event === 'stop') {
      cancelled = true;
      toApp('stop', null);
    } else if (msg.event === 'scanProgress') {
      toApp('scanProgress', Number(msg.data) || 0);
    }
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
      const label = String(args.text || '').slice(0, 120);
      if (tab) await askWa(tab.id, { cmd: 'overlay', text: label, hide: !!args.hide }, 3000).catch(() => {});
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
      const digits = phoneDigits(args.phone);
      const tab = await readyWaTab(`${WA_URL}send?phone=${digits}`, true);
      return await askWa(tab.id, { cmd: 'readChat' }, 80 * 1000);
    }

    case 'sendMessage': {
      if (cancelled) return 'cancelled';
      const digits = phoneDigits(args.phone);
      const text = cleanText(args.text);
      const media = cleanMedia(args.media);
      // Hard pacing, independent of the app's own delay.
      const wait = lastSendAt + LIMITS.minGapBetweenSendsMs - Date.now();
      if (wait > 0) await sleep(wait);
      lastSendAt = Date.now();
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
