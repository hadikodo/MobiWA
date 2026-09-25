# MobiWA - Local Lead Management & Message Recording

**MobiWA** is a local, privacy-first Android Flutter application for tracking customer leads, recording communication transcripts and inquiries, and detecting unsaved phone numbers by cross-referencing device contacts.

All data is stored strictly on-device in a local SQLite database. The application does not monitor, intercept, scrape, or extract communications from WhatsApp or any other third-party messaging applications.

---

## Key Features

1. **Local SQLite Database**:
   - `leads`: tracks phone numbers, contact names, notes, inquiry tags, lead stages (`New`, `Contacted`, `Qualified`, `Converted`, `Archived`), and timestamps.
   - `messages`: chronologically records incoming customer inquiries, outgoing quotations, and internal notes.
   - `contacts_cache`: stores phonebook comparison hashes to detect whether a lead is saved or unsaved in device contacts.

2. **Device Contacts Synchronization**:
   - User-authorized reading of contacts via Android's `ContactsContract` (`flutter_contacts`).
   - Phone number normalization and variant matching (handles country codes, local formats).
   - Instant unsaved-contact classification and one-tap "Save to Phone Contacts" capability.

3. **Dashboard & Metrics**:
   - Overview metrics: Total Leads, Unsaved Numbers, Messages Recorded, and Updates Today.
   - Quick Actions: Record Lead, Sync Device Contacts, Export to CSV.
   - Recent activity list with status chips, last inquiry snippets, and timestamps.

4. **Search & Multi-Filter Directory**:
   - Search across lead names, phone numbers, notes, and tags.
   - Full-text search across all recorded message contents and transcript notes.
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
- Android SDK (API Level 21+)

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
