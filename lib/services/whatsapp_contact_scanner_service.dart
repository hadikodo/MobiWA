// lib/services/whatsapp_contact_scanner_service.dart
import 'package:flutter/services.dart';

/// Bridges to the native WhatsAppContactScanner via a MethodChannel.
///
/// Queries Android's ContactsContract for phone numbers registered with
/// WhatsApp's sync adapter that are NOT saved in the user's device contacts.
/// Requires READ_CONTACTS permission.
class WhatsAppContactScannerService {
  static const _channel =
      MethodChannel('com.mobiwha.mobiwha/notification_capture');

  /// Scans for WhatsApp-associated phone numbers.
  ///
  /// If [onlyUnsaved] is true (default), returns only numbers that are NOT
  /// saved in the device contacts. If false, returns all WhatsApp-known numbers.
  ///
  /// Each result contains:
  /// - `phoneNumber`: e.g. "+961XXXXXXXX"
  /// - `displayName`: the name WhatsApp has for the contact (may be empty)
  static Future<List<ScannedWhatsAppContact>> scan({
    bool onlyUnsaved = true,
  }) async {
    try {
      final result = await _channel.invokeMethod(
        'scanWhatsAppContacts',
        {'onlyUnsaved': onlyUnsaved},
      );

      if (result == null) return [];

      final list = (result as List).cast<Map>();
      return list.map((m) {
        return ScannedWhatsAppContact(
          phoneNumber: (m['phoneNumber'] as String?) ?? '',
          displayName: (m['displayName'] as String?) ?? '',
        );
      }).where((c) => c.phoneNumber.isNotEmpty).toList();
    } on PlatformException {
      return [];
    }
  }
}

class ScannedWhatsAppContact {
  final String phoneNumber;
  final String displayName;

  const ScannedWhatsAppContact({
    required this.phoneNumber,
    required this.displayName,
  });

  @override
  String toString() =>
      'ScannedWhatsAppContact(phone: $phoneNumber, name: $displayName)';
}
