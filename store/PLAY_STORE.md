# Google Play — listing & declarations (copy/paste)

Package: **com.mobiwa.app** · Upload: `build/app/outputs/bundle/release/app-release.aab`

Assets in this folder:
- `play-store-icon-512.png` — app icon (512×512)
- `feature-graphic-1024x500.png` — feature graphic
- Phone screenshots: take 4–8 on the phone (Home, Get Numbers running, AI Sort results, Send, Categories). 1080×2400 is fine. Use test data, not real customers.

---

## Main store listing

**App name** (30): `MobiWA: WhatsApp Lead Sorter`

**Short description** (80):
`Collect WhatsApp leads, let AI sort your customers, and send offers automatically.`

**Full description** (≤4000):

```
MobiWA helps shops and businesses that sell on WhatsApp turn a messy chat list into organised customers — and reach them with the right offer.

★ 1 · GET NUMBERS
MobiWA scrolls through WhatsApp or WhatsApp Business and collects every chat from a number you never saved. New numbers land in an "Unnamed" list.

★ 2 · AI SORT
Our AI reads each chat you choose and decides: is this a customer? Customers are filed into a category named after what they asked for — "iPhone Repair", "Car Batteries", "Wedding Cakes"… Spam, wrong numbers and personal chats go to Junk. Works with your saved contacts too.

★ 3 · SEND MESSAGES
Pick categories, saved contacts or paste a list. Write your message — text, image, video or PDF with a caption — and press Send. MobiWA opens each chat, sends, and moves to the next, with a pause between messages. A STOP button is always on screen.

ALSO
• Team accounts with an admin dashboard (numbers, customers, messages per user)
• One account per device, remote sign-out for admins
• Works with WhatsApp and WhatsApp Business
• Web version at app.mobiwa.com (with WhatsApp Web)

PRIVACY
MobiWA only works inside WhatsApp when you start an action. Chat text is sent to our AI only to choose the category and is not stored. You can delete your account and data any time in Settings.

IMPORTANT
MobiWA uses Android's Accessibility service to work inside WhatsApp (see the in-app explanation). Only message people who agreed to hear from you. MobiWA is not affiliated with WhatsApp or Meta.
```

**Category:** Business · **Tags:** Customer management, Messaging, Productivity
**Contact email:** support@mobiwa.com · **Website:** https://mobiwa.com
**Privacy policy:** https://mobiwa.com/privacy

---

## App content (Policy → App content)

| Section | Answer |
|---|---|
| Privacy policy | https://mobiwa.com/privacy |
| Ads | No, the app does not contain ads |
| App access | **Restricted** — provide a test account: create user `play_review` (password ≥ 8 chars) in Admin → Users, and write: "Sign in with the username and password below. Accessibility must be enabled when prompted to use the 3 actions; WhatsApp must be installed and signed in." |
| Content rating | Questionnaire → category *Utility / Productivity*; no violence, sexual content, gambling, or user-generated content sharing → expected rating Everyone / PEGI 3 |
| Target audience | 18 and over only (business tool). Not designed for children. |
| News app | No |
| Government app | No |
| Financial features | None |
| Health | No |
| Data safety | see below |
| **Accessibility API** | see below — **required** |
| Account deletion | In-app: Settings → About → Delete my account. Web: https://mobiwa.com/delete-account |

---

## Accessibility API declaration (Policy → App content → Sensitive permissions)

- *Is your app an accessibility tool (`isAccessibilityTool`)?* **No.**
- *Core functionality that requires the AccessibilityService API:*

```
MobiWA is a lead-management tool for businesses that sell through WhatsApp. Its three core features need the AccessibilityService API because Android offers no other way to act inside WhatsApp:
1) Get Numbers: scrolls the user's WhatsApp chat list and reads the phone numbers shown for unsaved chats.
2) AI Sort: opens a chat the user selected and reads the messages on screen so they can be classified.
3) Send Messages: opens a chat, attaches the message the user prepared and presses Send.
The service only acts inside com.whatsapp and com.whatsapp.w4b, only while an action started by the user is running, shows a persistent STOP button during that time, and never reads other apps, passwords or the screen at other times. A prominent in-app disclosure is shown and the user must agree before being sent to the Accessibility settings.
```

- *Video:* record a 30–60 s screen recording (upload to YouTube unlisted): open MobiWA → tap Get Numbers → the disclosure dialog → "I agree" → Accessibility settings → enable "MobiWA Automation" → back → start Get Numbers and show the STOP bar.

---

## Data safety form

**Does your app collect or share user data?** Yes. **Encrypted in transit?** Yes. **Can users request deletion?** Yes.

| Data type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → Email / User IDs | Yes (username) | No | Required | Account management |
| Personal info → Phone number | Yes (customer numbers) | No | Required | App functionality |
| Messages → Other in-app messages | Yes (chat text for AI Sort, processed ephemerally) | No — Google Gemini processes it on our behalf as a service provider, which Google Play does not count as sharing | Optional (only when using AI Sort) | App functionality |
| Contacts | Yes (only contacts the user selects) | No | Optional | App functionality |
| App activity → Other actions | Yes (counts of numbers/messages) | No | Required | Analytics, App functionality |
| Device or other IDs | Yes (Android ID for one-device sign-in) | No | Required | Security, Account management |
| Files and docs / Photos / Videos | No — picked files are sent to WhatsApp on the device, not to our servers | — | — | — |

"Ephemeral processing": tick **Yes** for chat text (not stored).

---

## Release checklist

1. `flutter build appbundle --release` (signed with `android/upload-keystore.jks`).
2. Play Console → Create app → fill **App content** (above) → **Store listing**.
3. **Testing → Internal testing** first: upload the AAB, add testers, install from the Play link and run all three actions.
4. Enrol in **Play App Signing** (default). Keep `android/upload-keystore.jks` + `android/key.properties` backed up — they're needed for every update.
5. Production → Create release → roll out (start at 20 %).
6. For each update: bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) and `Config.appVersion`.
