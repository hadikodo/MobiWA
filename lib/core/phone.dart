/// Phone number helpers. Numbers are stored as "+<digits>" (international form).
class Phone {
  Phone._();

  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  static const _persian = '۰۱۲۳۴۵۶۷۸۹';

  static String _latinDigits(String s) {
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final a = _arabicIndic.indexOf(ch);
      final p = _persian.indexOf(ch);
      b.write(a >= 0 ? '$a' : (p >= 0 ? '$p' : ch));
    }
    return b.toString();
  }

  /// Turns user input into "+<digits>", or null if it is not a valid number.
  ///
  /// [defaultCountryCode] (digits only, e.g. "961") is applied to local
  /// numbers that start with a single 0.
  static String? normalize(String raw, {String defaultCountryCode = ''}) {
    final s = _latinDigits(raw.trim());
    if (s.isEmpty) return null;
    var digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (s.startsWith('+')) {
      // already international
    } else if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && defaultCountryCode.isNotEmpty) {
      digits = defaultCountryCode + digits.substring(1);
    } else if (defaultCountryCode.isNotEmpty && digits.length <= 8) {
      // Short local number without the leading 0 (e.g. Lebanese "70123456").
      digits = defaultCountryCode + digits;
    }

    if (digits.length < 8 || digits.length > 15) return null;
    return '+$digits';
  }

  /// Splits pasted text (one per line, or separated by commas/semicolons)
  /// into valid numbers and invalid entries.
  static ({List<String> valid, List<String> invalid}) parseList(
    String text, {
    String defaultCountryCode = '',
  }) {
    final valid = <String>{};
    final invalid = <String>[];
    for (final part in text.split(RegExp(r'[\n,;]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final n = normalize(t, defaultCountryCode: defaultCountryCode);
      if (n == null) {
        invalid.add(t);
      } else {
        valid.add(n);
      }
    }
    return (valid: valid.toList(), invalid: invalid);
  }

  /// Display form. Country-code lengths vary, so no grouping is guessed.
  static String pretty(String phone) => phone;
}
