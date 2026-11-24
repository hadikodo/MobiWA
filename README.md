# MobiWA

Turns WhatsApp chats into organised customer lists. **Going live? Read [DEPLOY.md](DEPLOY.md).**

## Repository

| Folder | What | Deploys to |
|---|---|---|
| `lib/`, `android/`, `web/` | Flutter app (Android + web) | Google Play `com.mobiwa.app` · **app.mobiwa.com** |
| `landing/` | Marketing site + Privacy / Terms / account deletion (React + Vite) | **mobiwa.com** |
| `extension/` | MobiWA Connector Chrome extension (web app ↔ WhatsApp Web) | Chrome Web Store |
| `supabase/` | Database migrations + Edge Functions | Supabase (live) |
| `store/` | Google Play listing texts, declarations, icon + feature graphic | Play Console |
| `branding/` | Logo SVGs; `python branding/render.py` regenerates every icon | — |

On Android the automation uses the Accessibility service; on the web it uses the
Chrome extension with WhatsApp Web. Both share one account, data and backend.

## What it does

Three steps:

1. **Get Numbers**: pick WhatsApp or WhatsApp Business. MobiWA opens it, scrolls the whole chat list, and collects every chat whose title is a phone number (a number you never saved). New numbers go into the **Unnamed** category.
2. **AI Sort**: for each Unnamed number, MobiWA opens the chat, reads the messages, and asks Gemini whether this is a customer.
   - Customer: filed into a category named after what they asked for (for example "iPhone Repair"). Existing categories are reused, and new ones are created when needed.
   - Not a customer (spam, wrong number, personal and so on): moved to **Junk**.
   - Chat couldn't be read: stays in Unnamed and is retried next time.
3. **Send Messages**: choose recipients (categories, single contacts, typed or pasted numbers, or any mix; duplicates are removed). Write a text message or attach an image, video or PDF with an optional caption, then press Send. MobiWA opens each chat, presses Send, closes the chat, waits, and moves to the next number.

While an action runs, a floating pill over WhatsApp shows the progress and has a **STOP** button. The screen stays awake for the whole run.

## Accounts and roles

Users sign in with a **username and password**. There is no public sign-up: an admin creates every account.

- **User**: runs the 3 steps on their own numbers and edits their own business info.
- **Admin**: everything a user can do, plus an **Admin** tab with:
  - **Dashboard**: totals for all users (users, numbers, customers, messages sent), a 14-day activity chart, and the top users.
  - **Users**: add, edit, disable or delete users, set roles and reset passwords. Open any user to see their business info, totals, categories and numbers, and to manage them.

## Backend (Supabase)

Project `lyrsxywtqalwelbgydbc`. Everything server-side is in `supabase/`:

| Piece | What it does |
|---|---|
| `migrations/` | Tables `profiles`, `categories`, `contacts`, `activity`. Row-level security means users see only their own rows and admins see everything. Triggers create each user's Unnamed and Junk categories. RPCs `admin_user_stats` and `admin_daily_activity` feed the dashboard. |
| `functions/ai-classify` | Reads a chat transcript and decides customer + category or Junk, using Gemini. The key is the `GEMINI_API_KEY` **Supabase secret**, so it never ships inside the app. Optional `GEMINI_MODEL` secret to pin a model. |
| `functions/admin-users` | Creates, updates, disables and deletes users with the service-role key (server only). Admin callers only. |
| `config.toml` | Public sign-ups are disabled (`[auth] enable_signup = false`). Keep `[auth.email] enable_signup = true`: it controls email/password login itself. |

The app ships only the **publishable** key (`lib/core/config.dart`). That key is meant to be public, because RLS protects the data.

Common commands (CLI already linked):

```
supabase db push                                   # apply new migrations
supabase functions deploy ai-classify --use-api
supabase functions deploy admin-users --use-api
supabase secrets set GEMINI_API_KEY=...            # rotate the Gemini key
```

Usernames without `@` are stored in Supabase Auth as `<username>@users.mobiwa.app`. The admin signs in with their email.

## One-time setup on each phone

1. **Accessibility**: Settings → Accessibility → Installed apps → **MobiWA Automation** → On.
   On Android 13+ sideloaded apps may show "Restricted setting". To fix it, open App info → ⋮ → *Allow restricted settings*, then try again.
2. Sign in, then in Settings fill in **My business** (it helps the AI decide) and your country code (so typed local numbers like `70 123 456` work).

## Project layout

```
lib/
  main.dart                    Supabase init, login gate, bottom navigation
  core/      config.dart (Supabase URL + publishable key), theme.dart, phone.dart
  data/      auth.dart (login, profile, admin API), db.dart (Supabase queries), models.dart, settings.dart
  services/  native.dart (Android bridge), gemini.dart (calls ai-classify), jobs.dart (the 3 actions), app_status.dart
  screens/   login, home, get_numbers, ai_sort, send, send_progress, contacts, category, settings
  screens/admin/  admin_screen (dashboard + users), admin_user_screen, user_form, activity_chart
android/app/src/main/kotlin/com/mobiwha/mobiwha/
  MainActivity.kt                    MethodChannel "com.mobiwha/automation", media picker, contacts, device info
  WhatsAppAccessibilityService.kt    scan / read chat / send jobs + floating Stop pill
supabase/    migrations, Edge Functions, config
```

## Notes and limits

- Sending media uses WhatsApp's share intent with a `jid` extra, which opens the file straight in the recipient's chat. This depends on WhatsApp's behaviour and screen layout, so check it on your WhatsApp version after updates.
- Unsaved-number detection relies on WhatsApp showing the phone number as the chat title. Archived chats are not scanned.
- Bulk messaging people who did not ask for it can get a WhatsApp account limited or banned. Keep a sensible pause between messages (Settings → Sending) and message people who expect to hear from you.

## Develop

```
flutter pub get
flutter analyze
flutter test
flutter run                      # Android phone
flutter run -d chrome            # web app (load extension/ unpacked in that Chrome)

cd landing && npm install && npm run dev   # landing page on http://localhost:5173
```

Production builds: `flutter build appbundle --release`, `flutter build web --release --no-web-resources-cdn`,
`cd landing && npm run build`. Details in [DEPLOY.md](DEPLOY.md).
