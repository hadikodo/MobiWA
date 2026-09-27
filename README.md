# MobiWA - Local Lead Management & Message Recording

**MobiWA** is a local, privacy-first Android Flutter application for tracking customer leads, capturing incoming WhatsApp notification previews, and detecting unsaved phone numbers by cross-referencing device contacts.

All app data is stored on-device in a local SQLite database. After the user enables Android notification access, MobiWA records incoming WhatsApp and WhatsApp Business notification previews and matches sender names against device contacts. Android requires one-time approval for both contacts and notification access. MobiWA does not access WhatsApp's private storage or decrypt backups.

---

## Key Features

1. **Local SQLite Database**:
   - `leads`: tracks phone numbers, contact names, notes, inquiry tags, lead stages (`New`, `Contacted`, `Qualified`, `Converted`, `Archived`), and timestamps.
   - `messages`: chronologically records incoming customer inquiries, outgoing quotations, and internal notes.
   - `contacts_cache`: stores locally synced phone numbers and names to detect whether a lead is saved or unsaved in device contacts.
   - `pending_notifications`: queues notification previews until a sender can be matched to a phone number.

2. **Device Contacts Synchronization**:
   - User-authorized reading of contacts via Android's `ContactsContract` (`flutter_contacts`).
   - Digits-only phone matching that avoids guessing country-code conversions and merging unrelated numbers.
   - Instant unsaved-contact classification and one-tap "Save to Phone Contacts" capability.

3. **Dashboard & Metrics**:
   - Overview metrics: Total Leads, Unsaved Numbers, Messages Recorded, and Updates Today.
   - Quick Actions: Record Lead, Sync Device Contacts, Export to CSV.
   - Recent activity list with status chips, last inquiry snippets, and timestamps.

4. **Search & Multi-Filter Directory**:
   - Search across lead names, phone numbers, notes, and tags.
   - Search across recorded message contents and transcript notes.
   - Filter by lead status and toggle "Unsaved Only".

5. **Lead Detail & Transcript Timeline**:
   - View and update lead details, stages, and customer requirements.
   - Chronological message history with incoming/outgoing badges.
   - Add new message records or notes.
   - Export individual conversation transcripts as CSV.

6. **Data Portability & Settings**:
   - CSV Export for all leads or unsaved leads.
   - CSV Import for loading leads from external spreadsheets.
   - Reset and clear local database with safety confirmations.
7. **WhatsApp Notification Capture**:
   - Captures incoming previews from WhatsApp and WhatsApp Business notifications.
   - Matches phone numbers or unique sender names to local device contacts.
   - Skips group summaries that do not identify a sender clearly.
8. **WhatsApp Draft Queue**:
   - Prepares personalized drafts for selected leads with recorded opt-in (`{{name}}`, `{{phone}}`).
   - Opens one recipient at a time in WhatsApp; the user reviews and taps Send. After confirming a send, MobiWA can open the next opted-in recipient's draft directly or stop the queue.
   - After returning, the user confirms whether the message was sent before MobiWA records it in the local transcript. MobiWA cannot verify delivery status.
   - The selected recipients, draft, and queue position survive app restarts; an interrupted recipient is shown for recovery.
9. **WhatsApp Chat Export Import**:
   - Accepts a shared plain-text chat export from WhatsApp or a user-selected `.txt` file through Android's document picker.
   - Keeps message timestamps and sender labels, classifies the configured self name as outgoing, and skips duplicate imports.
   - The user associates the export with a lead; media attachments and WhatsApp's private database are not read.
10. **Unmatched Preview Review**:
    - Keeps notification previews with unknown or ambiguous senders in a review queue.
    - Lets the user link each preview to an existing lead before saving it, avoiding silent drops or guessed contact matches.
    - Can create a lead from a phone number the user has verified, then attach the queued preview.

---

## Project Structure

```
lib/
├── main.dart                   # Application entry point, Material 3 theme & navigation
├── models/
│   ├── lead.dart               # Lead entity model
│   └── lead_message.dart       # Message and transcript history model
├── screens/
│   ├── home_screen.dart        # Dashboard KPI metrics and recent leads
│   ├── unsaved_screen.dart     # Unsaved phone numbers directory & save action
│   ├── messages_screen.dart    # Full search & filter across leads and message bodies
│   ├── detail_screen.dart      # Lead detail, editable notes, and transcript timeline
│   └── settings_screen.dart    # Permissions, contact sync, CSV export/import, data reset
├── services/
│   ├── database_service.dart   # SQLite database operations & queries
│   ├── contact_service.dart    # Android ContactsContract synchronization
│   └── export_service.dart     # CSV export, transcript sharing, and CSV import
└── utils/
    └── phone_utils.dart        # Phone normalization and variant matching
```

---

## Running the Application

### Prerequisites
- Flutter SDK (>= 3.0.0)
- Android SDK (API Level 26+)
- Android device or emulator (API Level 26+)

### WhatsApp message capture
On first launch, allow contacts access when Android asks. MobiWA syncs the phonebook into its local contact cache and seeds the Leads list from device contacts so the dashboard has real local records. In MobiWA Settings, open **WhatsApp Message Capture** and enable MobiWA in Android's notification access settings. Android requires this one-time approval. Only notification previews are captured; content WhatsApp does not show in notifications cannot be recorded.

Choosing **Clear All Local Data** pauses automatic phonebook imports so the deleted Leads list does not repopulate on the next launch. Use **Load Contacts into Leads** in Settings to import contacts again and re-enable automatic seeding.

### Commands
```bash
# Get dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit and widget test suite
flutter test

# Run app on connected device / emulator
flutter run
```
