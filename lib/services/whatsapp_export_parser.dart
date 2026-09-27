/// Parsed line from a user-selected WhatsApp plain-text chat export.
class WhatsAppExportMessage {
  const WhatsAppExportMessage({
    required this.timestamp,
    required this.sender,
    required this.text,
    required this.direction,
  });

  final int timestamp;
  final String sender;
  final String text;
  final String direction;
}

/// Parser for common Android and iOS WhatsApp .txt export line formats.
/// Multiline message bodies are retained. System-only event lines are skipped.
class WhatsAppExportParser {
  static final _startOfMessage = RegExp(
    r'^\[?([0-9\u0660-\u0669\u06f0-\u06f9]{1,4}[./-][0-9\u0660-\u0669\u06f0-\u06f9]{1,2}[./-][0-9\u0660-\u0669\u06f0-\u06f9]{1,4}),?\s+([0-9\u0660-\u0669\u06f0-\u06f9]{1,2}:[0-9\u0660-\u0669\u06f0-\u06f9]{2}(?::[0-9\u0660-\u0669\u06f0-\u06f9]{2})?\s*(?:AM|PM|am|pm|ص|م)?)\]?\s*(?:(?:-\s*|–\s*))?(.*)$',
  );
  static final _senderSeparator = RegExp(r'^(.{1,200}?):\s(.*)$', dotAll: true);

  static List<WhatsAppExportMessage> parse(
    String content, {
    String selfName = 'You',
    bool dayFirstForAmbiguousDates = true,
  }) {
    final normalized = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '');
    final result = <WhatsAppExportMessage>[];
    _PendingLine? pending;

    void flush() {
      final current = pending;
      pending = null;
      if (current == null) return;
      final match = _senderSeparator.firstMatch(current.content);
      if (match == null) return; // Encryption notices and system events.
      final sender = match.group(1)!.trim();
      final body = match.group(2)!.trim();
      if (sender.isEmpty || body.isEmpty) return;
      final lowerSender = sender.toLowerCase();
      final isSelf = lowerSender == selfName.toLowerCase() ||
          lowerSender == 'me' ||
          lowerSender == 'you';
      result.add(WhatsAppExportMessage(
        timestamp: current.timestamp,
        sender: sender,
        text: body,
        direction: isSelf ? 'outgoing' : 'incoming',
      ));
    }

    for (final line in normalized.split('\n')) {
      final start = _startOfMessage.firstMatch(line);
      if (start != null) {
        final timestamp = _parseTimestamp(
          _normalizeTimestampDigits(start.group(1)!),
          _normalizeTimestampDigits(start.group(2)!),
          dayFirstForAmbiguousDates: dayFirstForAmbiguousDates,
        );
        if (timestamp != null) {
          flush();
          pending = _PendingLine(timestamp, start.group(3) ?? '');
          continue;
        }
      }
      if (pending != null) {
        pending = pending!.append(line);
      }
    }
    flush();
    return result;
  }

  static int? _parseTimestamp(
    String date,
    String time, {
    required bool dayFirstForAmbiguousDates,
  }) {
    final dateParts = date.split(RegExp(r'[./-]'));
    if (dateParts.length != 3) return null;
    final firstText = dateParts[0];
    final first = int.tryParse(dateParts[0]);
    final second = int.tryParse(dateParts[1]);
    final third = int.tryParse(dateParts[2]);
    if (first == null || second == null || third == null) return null;

    final yearFirst = firstText.length == 4;
    var year = yearFirst ? first : third;
    if (year < 100) year += year >= 70 ? 1900 : 2000;

    // WhatsApp exports use the device locale. Resolve unambiguous dates first;
    // accept year-first locales and use the selected order for ambiguous dates.
    final day = yearFirst
        ? third
        : first > 12 || (second <= 12 && dayFirstForAmbiguousDates)
            ? first
            : second;
    final month = yearFirst
        ? second
        : first > 12 || (second <= 12 && dayFirstForAmbiguousDates)
            ? second
            : first;

    final timeMatch = RegExp(
      r'^([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?\s*(AM|PM|ص|م)?$',
      caseSensitive: false,
    ).firstMatch(time.trim());
    if (timeMatch == null) return null;
    var hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final secondOfMinute = int.tryParse(timeMatch.group(3) ?? '0') ?? 0;
    final marker = timeMatch.group(4)?.toUpperCase();
    final meridiem = switch (marker) {
      'م' => 'PM',
      'ص' => 'AM',
      _ => marker,
    };
    if (meridiem == 'PM' && hour < 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        hour > 23 ||
        minute > 59 ||
        secondOfMinute > 59) {
      return null;
    }
    final parsed = DateTime(year, month, day, hour, minute, secondOfMinute);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed.millisecondsSinceEpoch;
  }

  static String _normalizeTimestampDigits(String value) =>
      value.replaceAllMapped(RegExp(r'[\u0660-\u0669\u06f0-\u06f9]'), (match) {
        final codePoint = match.group(0)!.runes.single;
        final base = codePoint >= 0x06f0 ? 0x06f0 : 0x0660;
        return String.fromCharCode(0x30 + codePoint - base);
      });
}

class _PendingLine {
  const _PendingLine(this.timestamp, this.content);

  final int timestamp;
  final String content;

  _PendingLine append(String line) =>
      _PendingLine(timestamp, '$content\n$line');
}
