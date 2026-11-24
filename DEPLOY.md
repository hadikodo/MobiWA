# Going to production

> Security: read **[SECURITY.md](SECURITY.md)** first — especially the admin two-step verification.

| What | Where | Source | Host |
|---|---|---|---|
| Landing page | **mobiwa.com** | `landing/` (React + Vite) | Vercel / Netlify / Cloudflare Pages |
| Web app | **app.mobiwa.com** | this Flutter project, `flutter build web` | Vercel / Netlify / Cloudflare Pages |
| Android app | Google Play `com.mobiwa.app` | this Flutter project, `flutter build appbundle` | Google Play Console |
| MobiWA Connector (browser extension) | Chrome Web Store (public) | `extension/` | Chrome Web Store |
| Backend | Supabase project `lyrsxywtqalwelbgydbc` | `supabase/` | Supabase (already live) |

---

## 0. Before anything — fill in your company details

`landing/src/config.ts` → `company.legalName`, `company.address`, `company.jurisdiction`.
They appear in the Privacy Policy and Terms of Service. Have a lawyer review both pages
(`landing/src/pages/Privacy.tsx`, `Terms.tsx`) for your country.

Create the mailboxes used across the apps and pages: **support@**, **privacy@**, **sales@** `mobiwa.com`
(change them in `landing/src/config.ts` and `lib/core/config.dart` if different).

---

## 1. Backend (Supabase) — already deployed

Everything in `supabase/` is live: database + row-level security, the `ai-classify` and
`admin-users` Edge Functions, the `GEMINI_API_KEY` secret, sign-ups disabled.

After changing anything in `supabase/`:
```bash
supabase db push                                    # new migrations
supabase functions deploy ai-classify --use-api
supabase functions deploy admin-users --use-api
supabase secrets set GEMINI_API_KEY=...             # rotate the AI key
```

Recommended in the Supabase dashboard:
- **Upgrade to the Pro plan** before launch (free projects pause after inactivity, no backups).
- Authentication → URL configuration → Site URL: `https://app.mobiwa.com`.
- Database → Backups: confirm daily backups are on.
- Change the admin password (it was shared in chat): Admin → Users → your account → Edit.

---

## 2. Landing page → mobiwa.com

```bash
cd landing
npm install
npm run build          # → landing/dist
```
Environment variables (already in `landing/.env`, set the same on the host):
`VITE_SUPABASE_URL`, `VITE_SUPABASE_KEY` (publishable key — safe in the browser).

**Vercel:** New Project → import the repo → Root directory `landing` → Framework *Vite* →
add the two env vars → Deploy → Domains: add `mobiwa.com` and `www.mobiwa.com`.
(`landing/vercel.json` handles SPA routes like `/privacy` and security headers.)

**Netlify / Cloudflare Pages:** build command `npm run build`, output `dist`, base `landing`.
(`public/_redirects` and `public/_headers` are included.)

Check after deploy: `/`, `/privacy`, `/terms`, `/delete-account`, and send a test
message with the contact form → it appears in the app under **Admin → Inbox**.

---

## 3. Web app → app.mobiwa.com

```bash
flutter build web --release --no-web-resources-cdn   # → build/web (self-contained, no Google CDN)
```
Deploy the **`build/web`** folder:
- **Vercel:** `cd build/web && vercel --prod` (first time: link to a new project), then add the
  domain `app.mobiwa.com`. `vercel.json` (copied from `web/`) sets caching + headers.
- **Netlify / Cloudflare Pages:** drag-and-drop or CLI-deploy `build/web`; `_headers` is included.

The web app needs the **MobiWA Connector** extension + an open WhatsApp Web tab (see §5);
mobiwa.com/extension explains the setup to users.
Accounts are shared with Android; one account can be signed in on **one device at a time**
(a browser counts as a device).

---

## 4. Android → Google Play

Signing is set up: `android/upload-keystore.jks` + `android/key.properties` (git-ignored).
**Back both up** (password manager / safe storage) — without them you can't publish updates.

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
# → build/app/outputs/bundle/release/app-release.aab   (keep build/symbols to read crash reports)
```

> **This PC:** Android Studio's bundled Java is missing `awt.dll`, which makes the release
> *lint* step crash. Reinstall/repair Android Studio (or `flutter config --jdk-dir <full JDK 17+>`).
> Until then build with lint skipped:
> PowerShell `$env:MOBIWA_SKIP_LINT_VITAL=1; flutter build appbundle --release`

Then follow **`store/PLAY_STORE.md`** — store texts, Data safety answers, the Accessibility
declaration (needs a short screen recording), test account for reviewers, release steps.

Updates: bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) and `Config.appVersion` in
`lib/core/config.dart`, rebuild, upload.

> **Review risk:** Google restricts AccessibilityService use and WhatsApp's terms forbid
> unauthorised automation. The app includes the required disclosures, but approval is not
> guaranteed. If Play rejects the Accessibility use, the fallback is distributing the APK
> directly from mobiwa.com (`flutter build apk --release`) to your business customers.

Phone setup for users (also explained in the app): enable *MobiWA Automation* in Accessibility;
on Xiaomi/Redmi/POCO also allow **Autostart** and **No battery restrictions**. Optional, for
auto-restoring the automation after the phone kills it (support/IT only):
`adb shell pm grant com.mobiwa.app android.permission.WRITE_SECURE_SETTINGS`

---

## 5. MobiWA Connector → Chrome Web Store (public)

Publish it as described in **`extension/README.md`** (zip, upload, privacy answers, visibility
**Public**). After approval put the store link in `landing/src/config.ts` →
`site.chromeExtensionUrl` and redeploy the landing page: mobiwa.com/extension and the web app's
**Install** button then lead users to it. Microsoft Edge users can install from the Chrome Web
Store too (or publish the same zip on Edge Add-ons).

---

## 6. DNS (at your domain registrar)

| Record | Name | Value |
|---|---|---|
| A / ALIAS | `mobiwa.com` | from your landing host (Vercel: `76.76.21.21`) |
| CNAME | `www` | host-provided (Vercel: `cname.vercel-dns.com`) |
| CNAME | `app` | host-provided for the web-app project |
| MX + SPF/DKIM | `mobiwa.com` | from your email provider |

---

## 7. Launch checklist

- [ ] Company details filled in `landing/src/config.ts`; legal pages reviewed
- [ ] support@ / privacy@ / sales@ mailboxes working
- [ ] Supabase on a paid plan, backups on, admin password changed
- [ ] mobiwa.com live: all pages + contact form → Admin → Inbox
- [ ] Extension published (Public), store link set in `landing/src/config.ts`, landing redeployed
- [ ] app.mobiwa.com live, sign-in works, extension detected
- [ ] **Admin two-step verification set up** and admin password changed (see SECURITY.md)
- [ ] Extension published, store URL set on the landing page
- [ ] Play: internal testing done on a real phone (all 3 actions, text + image + video + PDF)
- [ ] Play: listing, Data safety, Accessibility declaration, account deletion URL submitted
- [ ] Keystore + key.properties backed up
