// MobiWA Connector — runs on web.whatsapp.com.
// Does on WhatsApp Web what the Android accessibility service does in the app:
// read the chat list, read one chat, send text / media, show a STOP bar.
// It only acts when the background script asks (i.e. when the user started an
// action in the MobiWA web app).
//
// WhatsApp Web changes its markup from time to time. Every selector lives in
// SEL below — update them there if an action stops working.

(() => {
  if (window.__mobiwaConnector) return;
  window.__mobiwaConnector = true;

  const SEL = {
    chatList: '#pane-side',
    chatRows: '#pane-side [role="listitem"], #pane-side [role="row"]',
    rowTitle: 'span[title]',
    conversation: '#main',
    composer: '#main footer [contenteditable="true"]',
    sendButton: [
      '#main footer button[aria-label="Send"]',
      '#main footer [data-icon="send"]',
      '#main footer [data-icon="wds-ic-send-filled"]',
    ],
    messages: '#main .message-in, #main .message-out',
    messageText: '.copyable-text[data-pre-plain-text] .selectable-text, .selectable-text.copyable-text',
    messageMeta: '[data-pre-plain-text]',
    // Media preview opened by pasting a file.
    mediaCaption: [
      'div[role="dialog"] [contenteditable="true"]',
      '[data-animate-modal-body] [contenteditable="true"]',
      'div[aria-label*="caption" i][contenteditable="true"]',
    ],
    mediaSend: [
      'div[role="dialog"] [data-icon="send"]',
      'div[role="dialog"] [data-icon="wds-ic-send-filled"]',
      '[data-animate-modal-body] [data-icon="send"]',
      'div[role="button"][aria-label="Send"]',
      'span[data-icon="send"]',
    ],
    dialog: 'div[role="dialog"], [data-animate-modal-popup]',
    loginMarkers: ['canvas[aria-label]', '[data-ref]', 'div[data-testid="qrcode"]'],
  };

  const INVALID_TEXT = [
    'phone number shared via url is invalid',
    'is not on whatsapp',
    "isn't on whatsapp",
    'غير صالح',
    'ليس على واتساب',
  ];

  let cancelled = false;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const first = (list, root = document) => {
    for (const s of list) {
      const el = root.querySelector(s);
      if (el) return el;
    }
    return null;
  };
  const clickable = (el) => (el ? el.closest('button, [role="button"]') || el : null);

  async function waitFor(fn, timeout = 15000, step = 250) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      if (cancelled) throw new Error('cancelled');
      const v = fn();
      if (v) return v;
      await sleep(step);
    }
    return null;
  }

  function state() {
    if ($(SEL.chatList)) return 'ready';
    if (SEL.loginMarkers.some((s) => $(s))) return 'login';
    return 'loading';
  }

  /** The "phone number is invalid / not on WhatsApp" popup, if shown. */
  function invalidPopup() {
    for (const d of $$(SEL.dialog)) {
      const t = (d.innerText || '').toLowerCase();
      if (INVALID_TEXT.some((x) => t.includes(x))) return d;
    }
    return null;
  }

  function dismiss(dialog) {
    const btn = dialog && $('button', dialog);
    if (btn) btn.click();
    else document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  }

  // ----------------------------------------------------------- STOP overlay

  let bar = null;
  function overlay(text, hide) {
    if (hide) {
      bar?.remove();
      bar = null;
      return;
    }
    if (!bar) {
      bar = document.createElement('div');
      bar.setAttribute('style', [
        'position:fixed', 'top:14px', 'left:50%', 'transform:translateX(-50%)', 'z-index:2147483647',
        'display:flex', 'align-items:center', 'gap:10px', 'padding:6px 6px 6px 16px',
        'background:rgba(17,27,33,.92)', 'color:#fff', 'border-radius:999px',
        'font:500 14px system-ui,sans-serif', 'box-shadow:0 8px 24px rgba(0,0,0,.3)',
      ].join(';'));
      const label = document.createElement('span');
      label.id = 'mobiwa-label';
      const stop = document.createElement('button');
      stop.textContent = 'STOP';
      stop.setAttribute('style',
        'border:0;border-radius:999px;padding:7px 14px;background:#E5484D;color:#fff;font:700 13px system-ui;cursor:pointer');
      stop.onclick = () => {
        cancelled = true;
        label.textContent = 'Stopping…';
        chrome.runtime.sendMessage({ kind: 'wa-event', event: 'stop' });
      };
      const logo = document.createElement('img');
      logo.src = chrome.runtime.getURL('icons/icon-32.png');
      logo.width = 20;
      logo.height = 20;
      bar.append(logo, label, stop);
      document.documentElement.appendChild(bar);
    }
    bar.querySelector('#mobiwa-label').textContent = text || 'MobiWA is working…';
  }

  // ------------------------------------------------------- 1. collect numbers

  /** "+961 70 123 456" → "+96170123456"; anything else → null. */
  function phoneFromTitle(raw) {
    if (!raw) return null;
    const latin = raw.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
      .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
    const compact = latin.replace(/[\s ‎‏‪-‮⁦-⁩()\-.]/g, '');
    return /^\+\d{7,15}$/.test(compact) ? compact : null;
  }

  function scrollerOf(el) {
    let n = el;
    while (n && n !== document.body) {
      const s = getComputedStyle(n);
      if (/(auto|scroll)/.test(s.overflowY) && n.scrollHeight > n.clientHeight + 10) return n;
      n = n.parentElement;
    }
    // Fallback: first scrollable descendant.
    return $$('*', el).find((c) => {
      const s = getComputedStyle(c);
      return /(auto|scroll)/.test(s.overflowY) && c.scrollHeight > c.clientHeight + 10;
    }) || el;
  }

  async function scan() {
    const pane = await waitFor(() => $(SEL.chatList), 20000);
    if (!pane) throw new Error('WhatsApp Web chat list not found.');
    const sc = scrollerOf(pane);
    sc.scrollTop = 0;
    await sleep(900);

    const found = new Set();
    let stagnant = 0;
    let lastReported = -1;
    for (let i = 0; i < 3000 && !cancelled; i++) {
      for (const row of $$(SEL.chatRows)) {
        const titleEl = $(SEL.rowTitle, row);
        const p = phoneFromTitle(titleEl && titleEl.getAttribute('title'));
        if (p) found.add(p);
      }
      if (found.size !== lastReported) {
        lastReported = found.size;
        chrome.runtime.sendMessage({ kind: 'wa-event', event: 'scanProgress', data: found.size });
        overlay(`Getting numbers… ${found.size} found`);
      }
      const before = sc.scrollTop;
      sc.scrollTop = before + sc.clientHeight * 0.8;
      await sleep(650);
      if (Math.abs(sc.scrollTop - before) < 2) {
        if (++stagnant >= 3) break;
      } else {
        stagnant = 0;
      }
    }
    sc.scrollTop = 0;
    return Array.from(found);
  }

  // ---------------------------------------------------------- 2. read a chat

  /** Waits for the chat opened by /send?phone= (or the invalid-number popup). */
  async function openedChat() {
    const r = await waitFor(() => {
      if (invalidPopup()) return 'invalid';
      if ($(SEL.composer)) return 'chat';
      return null;
    }, 25000);
    if (r === 'invalid') {
      dismiss(invalidPopup());
      return 'invalid';
    }
    return r;
  }

  function visibleMessages() {
    return $$(SEL.messages).map((m) => {
      const meta = $(SEL.messageMeta, m);
      const textEl = $(SEL.messageText, m);
      const text = (textEl ? textEl.innerText : '').trim();
      const pre = meta ? meta.getAttribute('data-pre-plain-text') || '' : '';
      const time = (pre.match(/^\[([^\]]+)\]/) || [])[1] || '';
      const key = (m.closest('[data-id]') || m).getAttribute('data-id') || `${time}|${text}`;
      return { key, text, time, direction: m.classList.contains('message-out') ? 'out' : 'in' };
    }).filter((m) => m.text);
  }

  async function readChat() {
    const opened = await openedChat();
    if (opened === 'invalid') return { status: 'not_on_whatsapp', messages: [] };
    if (!opened) throw new Error('Chat did not open.');
    await sleep(1200); // let bubbles render

    // Older messages appear above when scrolling up: prepend the new ones.
    const seen = new Set();
    let ordered = [];
    const addPage = () => {
      const fresh = visibleMessages().filter((m) => !seen.has(m.key));
      fresh.forEach((m) => seen.add(m.key));
      ordered = [...fresh, ...ordered];
      return fresh.length;
    };
    addPage();

    const firstMsg = $(SEL.messages);
    const sc = firstMsg ? scrollerOf(firstMsg) : null;
    for (let i = 0; i < 4 && sc && !cancelled; i++) {
      sc.scrollTop = 0;
      await sleep(1300);
      if (addPage() === 0) break;
    }
    const messages = ordered.slice(-80).map(({ text, time, direction }) => ({ text, time, direction }));
    return { status: 'ok', messages };
  }

  // ----------------------------------------------------------- 3. send

  function composerText() {
    const c = $(SEL.composer);
    return c ? (c.innerText || '').trim() : '';
  }

  function insertText(el, text) {
    el.focus();
    document.execCommand('insertText', false, text);
  }

  function base64ToFile(b64, name, mime) {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new File([bytes], name || 'file', { type: mime || 'application/octet-stream' });
  }

  async function sendText(text) {
    // The /send?text= link pre-fills the composer; type it ourselves if not.
    let ok = await waitFor(() => composerText().length > 0, 6000);
    if (!ok && text) {
      insertText($(SEL.composer), text);
      ok = await waitFor(() => composerText().length > 0, 3000);
    }
    if (!ok) return 'failed:empty_message';
    const btn = await waitFor(() => clickable(first(SEL.sendButton)), 8000);
    if (!btn) return 'failed:send_button_not_found';
    btn.click();
    const sent = await waitFor(() => composerText().length === 0, 8000);
    return sent ? 'sent' : 'failed:send_not_confirmed';
  }

  async function sendMedia(media, caption) {
    const composer = $(SEL.composer);
    const file = base64ToFile(media.base64, media.name, media.mime);
    const dt = new DataTransfer();
    dt.items.add(file);
    composer.focus();
    composer.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));

    // Media preview opens with a caption box and its own Send button.
    const sendBtn = await waitFor(() => clickable(first(SEL.mediaSend)), 20000, 400);
    if (!sendBtn) return 'failed:media_preview_not_opened';
    if (caption) {
      const box = first(SEL.mediaCaption);
      if (box) {
        insertText(box, caption);
        await sleep(300);
      }
    }
    clickable(first(SEL.mediaSend)).click();
    // Preview closes once WhatsApp starts sending (big videos take a while).
    const closed = await waitFor(() => !first(SEL.mediaCaption) && !!$(SEL.composer), 60000, 500);
    await sleep(1500);
    return closed ? 'sent' : 'failed:send_not_confirmed';
  }

  async function send({ text, media }) {
    const opened = await openedChat();
    if (opened === 'invalid') return 'not_on_whatsapp';
    if (!opened) return 'failed:chat_not_opened';
    await sleep(500);
    return media ? sendMedia(media, text) : sendText(text);
  }

  // ------------------------------------------------------------ dispatcher

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    const run = async () => {
      switch (msg.cmd) {
        case 'state':
          return state();
        case 'overlay':
          overlay(msg.text, msg.hide);
          return true;
        case 'cancel':
          cancelled = true;
          return true;
        case 'scan':
          cancelled = false;
          return scan();
        case 'readChat':
          cancelled = false;
          return readChat();
        case 'send':
          cancelled = false;
          return send(msg);
        default:
          throw new Error(`Unknown command ${msg.cmd}`);
      }
    };
    run()
      .then((result) => sendResponse({ ok: true, result }))
      .catch((e) => {
        const m = String((e && e.message) || e);
        if (m !== 'cancelled') return sendResponse({ ok: false, error: m });
        // STOP pressed: answer in the shape each command normally returns.
        const result = { send: 'cancelled', scan: [], readChat: { status: 'cancelled', messages: [] } }[msg.cmd];
        sendResponse({ ok: true, result: result ?? true });
      });
    return true;
  });
})();
