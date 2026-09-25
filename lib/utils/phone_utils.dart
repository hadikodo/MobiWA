// lib/utils/phone_utils.dart

class PhoneUtils {
  /// Normalizes a phone number to digits only (retaining '+' if present at the start)
  static String normalize(String raw) {
    final trimmed = raw.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  /// Extracts digits only without symbols or plus sign
  static String digitsOnly(String raw) {
    return raw.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Checks if a string looks like a valid phone number
  static bool looksLikePhoneNumber(String input) {
    final trimmed = input.trim();
    final digits = digitsOnly(trimmed);
    return digits.length >= 7 && digits.length <= 16;
  }

  /// Formats phone number for display if possible
  static String formatForDisplay(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return 'No Phone';
    return cleaned;
  }

  /// Generates comparison variants (e.g. with/without country code) to check against device contacts
  static Set<String> getVariants(String phone) {
    final digits = digitsOnly(phone);
    if (digits.isEmpty) return {};

    final set = <String>{digits};
    // If it starts with country code or 0, strip them
    if (digits.length > 10) {
      set.add(digits.substring(digits.length - 10)); // last 10 digits
    }
    if (digits.length > 9) {
      set.add(digits.substring(digits.length - 9)); // last 9 digits
    }
    if (digits.startsWith('0')) {
      set.add(digits.replaceFirst(RegExp(r'^0+'), ''));
    }
    return set;
  }
}
