# MobiWA security

How MobiWA is protected, and what you (the owner) must do to keep it that way.

## Your checklist (do these now)

1. **Set up two-step verification on your admin account.** Sign in → **Admin** tab → *Set up
   authenticator* → scan the QR code with Google Authenticator / Microsoft Authenticator /
   1Password → enter the code. Until you do this, the admin panel stays locked (by the server).
2. **Change your admin password** (it was shared in a chat): Admin → Users → your account → Edit.
   Use 10+ characters with letters and numbers (a password manager is best).
3. **Back up** `android/upload-keystore.jks` + `android/key.properties` somewhere offline/encrypted.
4. **Supabase dashboard:** upgrade to Pro, then Authentication → *Leaked password protection* ON,
   and keep daily backups on. Never share the `service_role` key — it is only used inside the
   Edge Functions.
5. **Publish the extension only through your Chrome Web Store developer account** (protect it
   with 2-step verification) and link only to the official store listing.
6. If you ever lose your authenticator: Supabase dashboard → Authentication → Users → your
   account → delete the MFA factor, then set it up again.

## What protects what

### Accounts & sign-in (Supabase Auth)
- Public sign-up is **disabled**; only an admin can create accounts (server-side function).
- Password policy: **≥ 10 characters, letters + digits** (server-enforced).
- Supabase rate-limits sign-in attempts (brute-force protection).
- **One account = one device**: each sign-in receives a random device token; the database
  only serves data to the device holding the current token. A copied session from another
  device gets nothing. Admins can force-sign-out a user (sessions revoked on the server).

### Admin (you)
- Every admin power requires a session verified with **two-step verification (TOTP, `aal2`)**:
  the database function `is_admin()` and the `admin-users` Edge Function both check it.
  A stolen admin password alone cannot read other users' data, the inbox or manage accounts.
- Admin role can only be granted by an existing admin (no hard-coded emails, no self-promotion:
  users can't write their own `role`, `active` or device columns).

### Data (Supabase Postgres)
- **Row-level security on every table.** Users see only their own rows, from their bound device.
- The device token column is not readable by clients (column-level grants).
- Contact-form messages: anyone can submit (length-limited, rate-limited per email and globally);
  only a verified admin can read them.
- Security-definer functions pin `search_path`; admin RPCs refuse non-admins.

### AI (Gemini)
- The Gemini API key lives only in **Supabase secrets** — never in the app, web app or extension.
- `ai-classify` requires a signed-in, active user on their bound device, caps input sizes,
  and enforces a **per-user quota (300/hour, 2000/day)** so a leaked account can't run up costs.
- Chat text is processed and not stored.

### Android app
- Session and device token are stored in **Keystore-encrypted storage** (not plain preferences).
- No backups of app data (`allowBackup=false`), HTTPS only, release builds shrunk with R8 and
  Dart code **obfuscated** (`--obfuscate --split-debug-info`).
- The accessibility service ignores all events and acts only on commands from the app itself;
  it only targets WhatsApp / WhatsApp Business. FileProvider is private and limited to the
  picked-media folder.

### Web app (app.mobiwa.com) and website (mobiwa.com)
- Strict **Content-Security-Policy** (no inline or third-party scripts; connections only to our
  Supabase), HSTS, no framing (clickjacking), no MIME sniffing, restrictive Permissions-Policy.
  Configured in `web/vercel.json` / `web/_headers` and `landing/vercel.json` / `landing/public/_headers`
  — keep them when you change hosting.
- Self-hosted fonts and rendering engine (no third-party CDN code).

### MobiWA Connector (browser extension)
- Talks **only** to `https://app.mobiwa.com` (top frame) and `https://web.whatsapp.com`;
  every message's sender and origin are verified; unknown commands are rejected.
- Inputs validated: phone numbers (7–15 digits), text ≤ 4096 chars, files only images /
  videos / PDF ≤ 64 MB; a hard minimum gap between sends.
- Strict extension CSP, no remote code, no `innerHTML`.
- Distributed only through the **Chrome Web Store** (signed by Google, reviewed, auto-updating).
  The website links only to the official listing and tells users never to install copies from
  anywhere else. Because the extension only answers app.mobiwa.com, a fake website can't use
  someone's installed extension to control their WhatsApp.

## Reporting a problem
Email security issues to support@mobiwa.com.
