# MobiWA Connector (browser extension)

Lets the MobiWA web app (**https://app.mobiwa.com**) run Get Numbers / AI Sort / Send inside
**WhatsApp Web** — the web equivalent of the Android app's Accessibility service. Users install it
from the Chrome Web Store; **mobiwa.com/extension** explains the setup.

```
app.mobiwa.com ──postMessage──▶ bridge.js ──runtime msg──▶ background.js ──tabs msg──▶ whatsapp.js (web.whatsapp.com)
```

| File | Role |
|---|---|
| `manifest.json` | MV3. Host access only to `web.whatsapp.com` and `app.mobiwa.com`. Strict CSP. |
| `bridge.js` | Content script on app.mobiwa.com only. Relays calls after checking origin + method. |
| `background.js` | Service worker. Verifies every sender, validates inputs (phone, text, file type/size), paces sends, drives the WhatsApp Web tab. |
| `whatsapp.js` | Content script on WhatsApp Web: scan chat list, read a chat, send text/media, STOP bar. **All selectors are in `SEL` at the top** — update there if WhatsApp changes its page. Obeys only this extension. |
| `popup.html/js` | Toolbar popup with connection status. |

Security details: see `../SECURITY.md`.

## Publish to the Chrome Web Store

1. Bump `"version"` in `manifest.json` (every update needs a higher version).
2. Zip the **contents** of this folder (not the folder itself):
   `Compress-Archive -Path extension\* -DestinationPath mobiwa-connector.zip -Force` (PowerShell).
3. https://chrome.google.com/webstore/devconsole (protect this Google account with 2-step
   verification) → New item → upload the zip.
4. **Store listing:** name *MobiWA Connector*, category *Productivity*, icon `icons/icon-128.png`,
   1–5 screenshots (1280×800) of the web app + WhatsApp Web with the STOP bar,
   website https://mobiwa.com, support https://mobiwa.com/#contact.
5. **Distribution:** visibility **Public**, all regions.
6. **Privacy practices** (answers):
   - *Single purpose:* "Connects the MobiWA web app to WhatsApp Web so the user can collect their chat numbers, have selected chats sorted by AI and send their own messages."
   - *Host permission `web.whatsapp.com`:* "To read the user's chat list / the chat they selected and to press Send for messages the user prepared, only when the user starts an action in the MobiWA web app."
   - *Host permission `app.mobiwa.com`:* "To receive commands from the MobiWA web app and return results."
   - *Remote code:* No.
   - *Data usage:* "Personally identifiable information" (phone numbers) and "Personal communications" (chat text, for AI sorting) — used only for the extension's single purpose; not sold; not used for unrelated purposes or creditworthiness.
   - *Privacy policy URL:* https://mobiwa.com/privacy
7. After approval, set `site.chromeExtensionUrl` in `landing/src/config.ts` to the store link
   and redeploy the landing page.

Microsoft Edge users can install from the Chrome Web Store; optionally also publish the same zip
on Edge Add-ons (https://partner.microsoft.com/dashboard/microsoftedge).

## Local development

1. `chrome://extensions` → **Developer mode** → **Load unpacked** → select this folder.
2. The connector only works on `https://app.mobiwa.com`. To test a local web build, temporarily add
   `"http://localhost/*"` to the bridge `matches` in `manifest.json` **and** to `ALLOWED_ORIGIN`
   in `bridge.js` / `APP_ORIGIN` in `background.js` — never publish with localhost enabled.
