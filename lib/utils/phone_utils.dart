// lib/utils/phone_utils.dart

class PhoneUtils {
  /// Normalizes a phone number to digits-only with country code for comparison.
  /// E.g. "+1 (555) 123-4567" → "15551234567"
  static String normalize(String raw) {
    return raw.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Checks if a string looks like a phone number (unsaved contact).
  /// WhatsApp shows unsaved numbers as "+XXXXXXXXXXXX" in notification titles.
  static bool looksLikePhoneNumber(String input) {
    final trimmed = input.trim();
    return RegExp(r'^\+?[\d\s\-().]{7,20}$').hasMatch(trimmed);
  }

  /// Extracts a phone number from a WhatsApp JID string.
  /// e.g. "15551234567@s.whatsapp.net" → "15551234567"
  /// e.g. "1234567890-1234567890@g.us" → null (group, skip)
  static String? extractFromJid(String jid) {
    if (jid.contains('@g.us')) return null; // group chat
    final parts = jid.split('@');
    if (parts.isEmpty) return null;
    final num = parts[0];
    // Validate it's actually a number
    if (RegExp(r'^\d{7,15}$').hasMatch(num)) return num;
    return null;
  }

  /// Returns all normalized variants of a phone number to match against contacts.
  /// Handles missing/extra country codes.
  static List<String> variants(String normalized) {
    final results = <String>{normalized};
    // Strip leading country codes to get local number variants
    if (normalized.length > 10) {
      results.add(normalized.substring(normalized.length - 10));
    }
    if (normalized.length > 11) {
      results.add(normalized.substring(normalized.length - 11));
    }
    // Add with common country code prefixes if short
    if (normalized.length == 10) {
      results.add('1$normalized'); // US/CA
      results.add('44$normalized'); // UK (though UK is typically 11 digits)
    }
    return results.toList();
  }
}
