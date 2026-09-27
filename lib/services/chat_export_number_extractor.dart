// lib/services/chat_export_number_extractor.dart

import '../utils/phone_utils.dart';

/// Extracts unique phone numbers from one or more WhatsApp chat export files.
///
/// Unlike the full [WhatsAppExportParser], this does NOT import message
/// content — it only scans for phone numbers in the chat metadata
/// (file name, sender names in the chat header).
///
/// Use this to bulk-import historical unsaved customer numbers from
/// WhatsApp chat exports without needing to process individual messages.
class ChatExportNumberExtractor {
  /// Extracts unique phone numbers from one or more chat export text contents.
  ///
  /// Returns a list of [ExtractedNumber] with the phone number and any
  /// context about where it was found (file name, sender line, etc.).
  static List<ExtractedNumber> extractFromExports(
    List<ChatExportFile> exports,
  ) {
    final seen = <String>{};
    final results = <ExtractedNumber>[];

    for (final export in exports) {
      // 1. Try to extract phone number from the file name
      //    e.g. "WhatsApp Chat with +961 81 333 269.txt"
      final fileNameNumbers = _extractPhonesFromText(export.fileName);
      for (final phone in fileNameNumbers) {
        final digits = PhoneUtils.digitsOnly(phone);
        if (seen.add(digits)) {
          results.add(ExtractedNumber(
            phoneNumber: phone,
            source: 'File: ${export.fileName}',
          ));
        }
      }

      // 2. Scan the first 200 lines for sender patterns that look like phone numbers
      final lines = export.content.split('\n');
      final linesToScan = lines.length > 200 ? lines.sublist(0, 200) : lines;

      for (final line in linesToScan) {
        // Match WhatsApp chat line format: "date, time - sender: message"
        // We care about the sender part when it looks like a phone number
        final senderMatch = _chatLineSender.firstMatch(line);
        if (senderMatch != null) {
          final sender = senderMatch.group(1)?.trim() ?? '';
          if (_looksLikePhoneNumber(sender)) {
            final normalized = PhoneUtils.normalize(sender);
            final digits = PhoneUtils.digitsOnly(normalized);
            if (digits.isNotEmpty && seen.add(digits)) {
              results.add(ExtractedNumber(
                phoneNumber: normalized,
                source: 'Chat sender',
              ));
            }
          }
        }
      }

      // 3. Also check for phone numbers in the full content using a broad regex
      //    This catches numbers that appear as senders throughout the chat
      final allSenders = <String>{};
      for (final line in lines) {
        final match = _chatLineSender.firstMatch(line);
        if (match != null) {
          final sender = match.group(1)?.trim() ?? '';
          allSenders.add(sender);
        }
      }

      for (final sender in allSenders) {
        if (_looksLikePhoneNumber(sender)) {
          final normalized = PhoneUtils.normalize(sender);
          final digits = PhoneUtils.digitsOnly(normalized);
          if (digits.isNotEmpty && seen.add(digits)) {
            results.add(ExtractedNumber(
              phoneNumber: normalized,
              source: 'Chat sender',
            ));
          }
        }
      }
    }

    return results;
  }

  /// Extracts phone numbers from a single text string (e.g. file name).
  static List<String> _extractPhonesFromText(String text) {
    final matches = _phonePattern.allMatches(text);
    return matches
        .map((m) => PhoneUtils.normalize(m.group(0) ?? ''))
        .where((p) => PhoneUtils.looksLikePhoneNumber(p))
        .toList();
  }

  static bool _looksLikePhoneNumber(String text) {
    final cleaned = text.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (!cleaned.startsWith('+') && !RegExp(r'^\d').hasMatch(cleaned)) {
      return false;
    }
    final digits = PhoneUtils.digitsOnly(cleaned);
    return digits.length >= 7 && digits.length <= 15;
  }

  // Matches phone-like patterns: +961 81 333 269, 09611234567, etc.
  static final _phonePattern = RegExp(
    r'\+?\d[\d\s\-\(\)\.]{5,}\d',
  );

  // Matches the sender part of a WhatsApp chat line
  // Handles both formats:
  //   [1/1/24, 12:00 PM] Sender: message
  //   1/1/24, 12:00 PM - Sender: message
  static final _chatLineSender = RegExp(
    r'(?:[\[\d][\d/.\-,:\s\u0660-\u0669\u06f0-\u06f9AaPpMm\u0635\u0645]+[\]]\s*|'
    r'[\d][\d/.\-,:\s\u0660-\u0669\u06f0-\u06f9AaPpMm\u0635\u0645]+\s*[-–]\s*)'
    r'(.+?):\s',
  );
}

class ChatExportFile {
  final String fileName;
  final String content;

  const ChatExportFile({
    required this.fileName,
    required this.content,
  });
}

class ExtractedNumber {
  final String phoneNumber;
  final String source;

  const ExtractedNumber({
    required this.phoneNumber,
    required this.source,
  });
}
