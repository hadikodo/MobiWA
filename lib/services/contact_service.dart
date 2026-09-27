// lib/services/contact_service.dart
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database_service.dart';
import '../models/lead.dart';
import '../utils/phone_utils.dart';

class ContactService {
  static Map<String, String> _contactsMap = {};
  static DateTime? _lastSyncTime;

  static DateTime? get lastSyncTime => _lastSyncTime;
  static int get cachedCount => _contactsMap.length;

  static void clearInMemoryCache() {
    _contactsMap = {};
    _lastSyncTime = null;
  }

  /// Check if contacts permission is currently granted
  static Future<bool> hasPermission() async {
    final status = await Permission.contacts.status;
    return status.isGranted;
  }

  /// Explicitly request contacts permission from the user
  static Future<bool> requestPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  /// Synchronize device contacts and reclassify local leads
  /// Returns the number of contacts synchronized, or -1 if permission denied.
  static Future<int> syncContacts() async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return -1;
    }

    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> map = {};

      for (final contact in contacts) {
        final name = contact.displayName.trim();
        for (final phone in contact.phones) {
          final normalizedPhone = phone.normalizedNumber.trim();
          final digits = PhoneUtils.digitsOnly(
            normalizedPhone.isEmpty ? phone.number : normalizedPhone,
          );
          if (PhoneUtils.looksLikePhoneNumber(digits)) map[digits] = name;
        }
      }

      _contactsMap = map;
      _lastSyncTime = DateTime.now();

      // Persist to local contacts cache table
      await DatabaseService.syncContactsCache(map);

      // Re-evaluate all leads in the database
      final leads = await DatabaseService.getLeads(limit: 10000);
      for (final lead in leads) {
        final digits = PhoneUtils.digitsOnly(lead.phoneNumber);
        bool found = false;
        String contactName = '';

        for (final variant in PhoneUtils.getVariants(digits)) {
          if (map.containsKey(variant)) {
            found = true;
            contactName = map[variant] ?? '';
            break;
          }
        }

        final isUnsaved = !found;
        if (lead.isUnsaved != isUnsaved ||
            (found && lead.name.isEmpty && contactName.isNotEmpty)) {
          await DatabaseService.updateLeadClassification(
            lead.id!,
            isUnsaved,
            contactName: lead.name.isEmpty ? contactName : null,
          );
        }
      }

      DatabaseService.notifyDataChanged();
      return contacts.length;
    } catch (e) {
      return -1;
    }
  }

  /// Copies device contact phone numbers into the local lead directory.
  /// Returns the number of newly created lead records, or -1 on failure.
  static Future<int> importDeviceContactsAsLeads() async {
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return -1;
    }

    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      var imported = 0;
      final seenPhones = <String>{};
      for (final contact in contacts) {
        final name = contact.displayName.trim();
        for (final phoneEntry in contact.phones) {
          final normalizedPhone = phoneEntry.normalizedNumber.trim();
          final phone = PhoneUtils.normalize(
              normalizedPhone.isEmpty ? phoneEntry.number : normalizedPhone);
          if (!PhoneUtils.looksLikePhoneNumber(phone) ||
              !seenPhones.add(phone)) {
            continue;
          }
          if (await DatabaseService.getLeadByPhone(phone) != null) continue;
          await DatabaseService.getOrCreateLead(
            phoneNumber: phone,
            name: name,
            isUnsaved: false,
            notify: false,
          );
          imported++;
        }
      }
      if (imported > 0) DatabaseService.notifyDataChanged();
      return imported;
    } catch (_) {
      return -1;
    }
  }

  /// Determines whether a given phone number is unsaved in the contacts cache
  static bool isNumberUnsaved(String phone) {
    final digits = PhoneUtils.digitsOnly(phone);
    if (digits.isEmpty) return true;

    for (final variant in PhoneUtils.getVariants(digits)) {
      if (_contactsMap.containsKey(variant)) {
        return false;
      }
    }
    return true;
  }

  /// Save an unsaved lead as a contact on the user's device
  static Future<bool> saveToDeviceContacts(Lead lead) async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    try {
      final newContact = Contact()
        ..name.first =
            lead.name.isNotEmpty ? lead.name : 'Lead ${lead.phoneNumber}'
        ..phones = [Phone(lead.phoneNumber)];

      if (lead.notes.isNotEmpty) {
        newContact.notes = [Note(lead.notes)];
      }

      await newContact.insert();
      // Re-sync after inserting
      await syncContacts();
      return true;
    } catch (e) {
      return false;
    }
  }
}
