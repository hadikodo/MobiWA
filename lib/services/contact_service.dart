// lib/services/contact_service.dart
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database_service.dart';
import '../utils/phone_utils.dart';

class ContactService {
  /// Device contacts cache: normalized_phone → display_name
  static Map<String, String> _cache = {};
  static DateTime? _lastSync;

  /// Request contacts permission and sync to local DB
  static Future<bool> requestAndSync() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return false;
    await syncContacts();
    return true;
  }

  /// Sync device contacts into local DB cache
  static Future<void> syncContacts() async {
    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> phoneToName = {};
      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final normalized = PhoneUtils.normalize(phone.number);
          if (normalized.isNotEmpty) {
            phoneToName[normalized] = contact.displayName;
            // Also store all variants
            for (final v in PhoneUtils.variants(normalized)) {
              phoneToName[v] = contact.displayName;
            }
          }
        }
      }
      _cache = phoneToName;
      _lastSync = DateTime.now();
      await DatabaseService.syncContacts(phoneToName);
      // Re-classify all existing leads
      await _reclassifyLeads();
    } catch (e) {
      // Permission denied or error — continue without contacts
    }
  }

  /// Check if a sender name/number is an unsaved contact
  static bool isUnsaved(String sender) {
    // If it doesn't look like a phone number, it's likely a saved contact name
    if (!PhoneUtils.looksLikePhoneNumber(sender)) return false;

    final normalized = PhoneUtils.normalize(sender);
    if (_cache.containsKey(normalized)) return false;

    // Check variants
    for (final v in PhoneUtils.variants(normalized)) {
      if (_cache.containsKey(v)) return false;
    }
    return true;
  }

  /// After syncing contacts, re-classify all leads in DB
  static Future<void> _reclassifyLeads() async {
    final leads = await DatabaseService.getAllLeads(limit: 10000);
    for (final lead in leads) {
      final nowUnsaved = isUnsaved(lead.sender);
      if (nowUnsaved != lead.isUnsaved) {
        await DatabaseService.markSenderUnsaved(lead.sender, nowUnsaved);
      }
    }
  }

  static bool get isSynced => _lastSync != null;
  static int get cachedCount => _cache.length;
}
