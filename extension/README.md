# MobiWA Connector (Chrome extension)

Lets the MobiWA web app (**app.mobiwa.com**) work inside **WhatsApp Web** — the web
equivalent of the Android app's Accessibility service.

```
app.mobiwa.com ──postMessage──▶ bridge.js ──runtime msg──▶ background.js ──tabs msg──▶ whatsapp.js (web.whatsapp.com)
```

| File | Role |
|---|---|
| `manifest.json` | Manifest V3. Host access only to `web.whatsapp.com` and `app.mobiwa.com`. |
| `bridge.js` | Content script on the web app. Relays calls/results/events. |
| `background.js` | Service worker. Finds/opens/focuses the WhatsApp Web tab, navigates to chats (`/send?phone=`), forwards commands. |
| `whatsapp.js` | Content script on WhatsApp Web: scan chat list, read a chat, send text or media (+caption), STOP bar. **All selectors are in `SEL` at the top** — update there if WhatsApp changes its page. |
| `popup.html/js` | Toolbar popup with connection status. |

Methods the web app calls (see `lib/services/native.dart`): `status`, `openWhatsApp`,
`focusApp`, `overlay`, `cancel`, `scanUnsaved`, `readChat`, `sendMessage`.

## Develop / test

1. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → select this folder.
2. Run the web app locally (`flutter run -d chrome` or serve `build/web` on `http://localhost:<port>`; localhost is allowed).
3. Open `web.whatsapp.com` in the same browser and link it.

## Publish to the Chrome Web Store

1. Zip the **contents** of this folder (not the folder itself):
   `Compress-Archive -Path extension\* -DestinationPath mobiwa-connector.zip` (PowerShell).
2. https://chrome.google.com/webstore/devconsole → New item → upload the zip.
3. Listing: name *MobiWA Connector*, category *Productivity*, icon `icons/icon-128.png`,
   screenshots 1280×800 of the web app + WhatsApp Web with the STOP bar.
4. **Privacy practices tab** (answers):
   - *Single purpose:* "Connects the MobiWA web app to WhatsApp Web so the user can collect their chat numbers, have selected chats sorted by AI and send their own messages."
   - *Host permission `web.whatsapp.com`:* "To read the user's chat list / opened chat and to press Send for messages the user prepared, only when the user starts an action in the MobiWA web app."
   - *Host permission `app.mobiwa.com`:* "To receive commands from the MobiWA web app and return results."
   - *Data usage:* collects "Personally identifiable information" (phone numbers) and "Personal communications" (chat text, for AI sorting) — used only for the app's functionality, not sold, not used for unrelated purposes, not used for creditworthiness.
   - *Privacy policy URL:* https://mobiwa.com/privacy
5. After approval, put the store URL in `landing/src/config.ts` → `site.chromeExtensionUrl` and redeploy the landing page.

Bump `"version"` in `manifest.json` for every update.
