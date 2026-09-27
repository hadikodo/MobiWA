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
    return digits.length >= 7 && digits.length <= 15;
  }

  /// Formats phone number for display if possible
  static String formatForDisplay(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return 'No Phone';
    return cleaned;
  }

  /// Returns only lossless comparison forms for a phone number.
  ///
  /// Removing arbitrary trailing digits can incorrectly merge unrelated
  /// international numbers. Country-code conversion needs an explicit region
  /// and is deliberately not guessed here.
  static Set<String> getVariants(String phone) {
    final digits = digitsOnly(phone);
    if (digits.isEmpty) return {};
    return {digits};
  }
}
