// Shows whether WhatsApp Web is open and linked.
const labels = {
  ready: ['ok', 'WhatsApp Web connected'],
  login: ['warn', 'Link WhatsApp Web (scan the QR code)'],
  loading: ['warn', 'WhatsApp Web is loading…'],
  closed: ['', 'WhatsApp Web is not open'],
};

chrome.runtime.sendMessage({ kind: 'call', method: 'status', args: {} }, (resp) => {
  const state = (resp && resp.ok && resp.result && resp.result.whatsapp) || 'closed';
  const [cls, text] = labels[state] || labels.closed;
  document.getElementById('wa-dot').className = `dot ${cls}`;
  document.getElementById('wa-text').textContent = text;
});

document.getElementById('open-wa').addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.sendMessage({ kind: 'call', method: 'openWhatsApp', args: {} });
  window.close();
});
