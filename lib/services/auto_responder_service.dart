// lib/services/auto_responder_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../utils/phone_utils.dart';
import 'database_service.dart';
import 'gemini_service.dart';
import 'whatsapp_service.dart';

class AutoResponderSettings {
  final bool isEnabled;
  final String instructions;
  final String tone;
  final bool learnFromHistory;
  final int delaySeconds;
  final String targetApp; // 'both', 'com.whatsapp', 'com.whatsapp.w4b'
  final String respondMode; // 'all', 'unsaved_only', 'saved_only', 'specific_list', 'specific_numbers'
  final String targetAiList; // CRM list if respondMode == 'specific_list'
  final String whitelistNumbers; // numbers or names allowed
  final String excludedNumbers; // numbers or names never to reply to
  final bool ignoreGroups; // true = do not reply in group chats

  const AutoResponderSettings({
    this.isEnabled = false,
    this.instructions = '',
    this.tone = 'Match My Style',
    this.learnFromHistory = true,
    this.delaySeconds = 2,
    this.targetApp = 'both',
    String? respondMode,
    this.targetAiList = 'Hot Leads',
    this.whitelistNumbers = '',
    this.excludedNumbers = '',
    this.ignoreGroups = true,
    bool? replyToAll,
  }) : respondMode = respondMode ?? (replyToAll == false ? 'unsaved_only' : 'all');

  bool get enabled => isEnabled;
  bool get replyToAll => respondMode == 'all';

  AutoResponderSettings copyWith({
    bool? isEnabled,
    String? instructions,
    String? tone,
    bool? learnFromHistory,
    int? delaySeconds,
    String? targetApp,
    String? respondMode,
    String? targetAiList,
    String? whitelistNumbers,
    String? excludedNumbers,
    bool? ignoreGroups,
  }) {
    return AutoResponderSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      instructions: instructions ?? this.instructions,
      tone: tone ?? this.tone,
      learnFromHistory: learnFromHistory ?? this.learnFromHistory,
      delaySeconds: delaySeconds ?? this.delaySeconds,
      targetApp: targetApp ?? this.targetApp,
      respondMode: respondMode ?? this.respondMode,
      targetAiList: targetAiList ?? this.targetAiList,
      whitelistNumbers: whitelistNumbers ?? this.whitelistNumbers,
      excludedNumbers: excludedNumbers ?? this.excludedNumbers,
      ignoreGroups: ignoreGroups ?? this.ignoreGroups,
    );
  }
}

class AutoResponderLog {
  final int id;
  final String phoneNumber;
  final String senderName;
  final String incomingMessage;
  final String replyText;
  final int timestamp;
  final bool success;
  final String? error;

  AutoResponderLog({
    required this.id,
    required this.phoneNumber,
    required this.senderName,
    required this.incomingMessage,
    required this.replyText,
    required this.timestamp,
    required this.success,
    this.error,
  });
}

class AutoResponderService {
  static const String _prefEnabled = 'auto_responder_enabled';
  static const String _prefInstructions = 'auto_responder_instructions';
  static const String _prefTone = 'auto_responder_tone';
  static const String _prefLearn = 'auto_responder_learn_from_history';
  static const String _prefDelay = 'auto_responder_delay_sec';
  static const String _prefReplyToAll = 'auto_responder_reply_to_all';
  static const String _prefTargetApp = 'auto_responder_target_app';
  static const String _prefRespondMode = 'auto_responder_respond_mode';
  static const String _prefTargetAiList = 'auto_responder_target_ai_list';
  static const String _prefWhitelist = 'auto_responder_whitelist';
  static const String _prefExcluded = 'auto_responder_excluded';
  static const String _prefIgnoreGroups = 'auto_responder_ignore_groups';

  static final List<AutoResponderLog> recentLogs = [];
  static final ValueNotifier<int> logRevision = ValueNotifier<int>(0);
  static final Set<String> _processedNotificationKeys = {};

  /// Loads current auto-responder configuration
  static Future<AutoResponderSettings> getSettings() async {
    final db = await DatabaseService.database;
    final rows = await db.query('app_preferences');
    final map = {
      for (final r in rows)
        r['preference_key'].toString(): r['preference_value']?.toString() ?? ''
    };

    final rawMode = map[_prefRespondMode];
    final mode = (rawMode != null && rawMode.isNotEmpty)
        ? rawMode
        : (map[_prefReplyToAll] == '0' ? 'unsaved_only' : 'all');

    return AutoResponderSettings(
      isEnabled: map[_prefEnabled] == '1',
      instructions: map[_prefInstructions] ?? '',
      tone: map[_prefTone]?.isNotEmpty == true ? map[_prefTone]! : 'Match My Style',
      learnFromHistory: map[_prefLearn] != '0',
      delaySeconds: int.tryParse(map[_prefDelay] ?? '') ?? 2,
      targetApp: map[_prefTargetApp]?.isNotEmpty == true ? map[_prefTargetApp]! : 'both',
      respondMode: mode,
      targetAiList: map[_prefTargetAiList]?.isNotEmpty == true ? map[_prefTargetAiList]! : 'Hot Leads',
      whitelistNumbers: map[_prefWhitelist] ?? '',
      excludedNumbers: map[_prefExcluded] ?? '',
      ignoreGroups: map[_prefIgnoreGroups] != '0',
    );
  }

  /// Saves auto-responder configuration
  static Future<void> saveSettings(AutoResponderSettings settings) async {
    final db = await DatabaseService.database;
    final batch = db.batch();

    final pairs = {
      _prefEnabled: settings.isEnabled ? '1' : '0',
      _prefInstructions: settings.instructions.trim(),
      _prefTone: settings.tone,
      _prefLearn: settings.learnFromHistory ? '1' : '0',
      _prefDelay: settings.delaySeconds.toString(),
      _prefReplyToAll: settings.replyToAll ? '1' : '0',
      _prefTargetApp: settings.targetApp,
      _prefRespondMode: settings.respondMode,
      _prefTargetAiList: settings.targetAiList,
      _prefWhitelist: settings.whitelistNumbers.trim(),
      _prefExcluded: settings.excludedNumbers.trim(),
      _prefIgnoreGroups: settings.ignoreGroups ? '1' : '0',
    };

    for (final entry in pairs.entries) {
      batch.insert(
        'app_preferences',
        {'preference_key': entry.key, 'preference_value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    DatabaseService.notifyDataChanged();
  }

  /// Samples real past outgoing messages sent by the WhatsApp owner to learn
  /// their unique speaking tone, dialect, greetings, and typical phrases.
  static Future<List<String>> getOwnerStyleSamples({int limit = 15}) async {
    try {
      final db = await DatabaseService.database;
      final rows = await db.rawQuery('''
        SELECT message FROM messages
        WHERE direction = 'outgoing'
          AND (note IS NULL OR note NOT LIKE '%Auto-Reply%')
          AND LENGTH(TRIM(message)) > 2
        ORDER BY timestamp DESC
        LIMIT ?
      ''', [limit]);

      return rows
          .map((r) => r['message']?.toString().trim() ?? '')
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Formulates prompt and generates an AI reply tailored to the customer
  /// and matching the owner's learned communication style.
  static Future<String?> generateReply({
    required Lead lead,
    required String incomingMessage,
    List<LeadMessage>? history,
  }) async {
    final settings = await getSettings();
    final ownerSamples = settings.learnFromHistory
        ? await getOwnerStyleSamples(limit: 15)
        : <String>[];

    final chatHistory = history ??
        (lead.id != null
            ? await DatabaseService.getMessagesForLead(lead.id!)
            : <LeadMessage>[]);

    final historyBuffer = StringBuffer();
    if (chatHistory.isNotEmpty) {
      final recent = chatHistory.length > 10
          ? chatHistory.sublist(chatHistory.length - 10)
          : chatHistory;
      for (final m in recent) {
        final sender = m.direction == 'outgoing' ? 'Owner' : 'Customer';
        historyBuffer.writeln('[$sender]: ${m.message}');
      }
    } else {
      historyBuffer.writeln('(No prior conversation history)');
    }

    final styleText = ownerSamples.isNotEmpty
        ? ownerSamples.map((s) => '• "$s"').join('\n')
        : '(No past outgoing messages found. Be friendly, authentic, and direct.)';

    final prompt = '''
You are the AI Auto-Responder chatting directly on behalf of the WhatsApp account owner.
Listen carefully to the customer's incoming message and give them an accurate, helpful response that sounds exactly like the owner talking.

--- HOW THE OWNER TALKS (REAL SAMPLES FROM PAST OUTGOING CHATS) ---
$styleText

--- BUSINESS GUIDELINES & CONTEXT ---
${settings.instructions.trim().isNotEmpty ? settings.instructions : 'Provide accurate, friendly customer support and sales assistance.'}

--- TONE PREFERENCE ---
${settings.tone}

--- CUSTOMER PROFILE ---
Name: ${lead.displayName}
Phone: ${lead.phoneNumber}
Lists / Segments: ${lead.aiList.isNotEmpty ? lead.aiList : 'General'}
Customer Summary: ${lead.aiSummary.isNotEmpty ? lead.aiSummary : 'New contact'}

--- RECENT CONVERSATION HISTORY ---
$historyBuffer

--- INCOMING MESSAGE TO REPLY TO ---
"$incomingMessage"

--- RESPONSE RULES ---
1. Language & Dialect: Match the language and dialect of the incoming message and owner style (e.g. Arabic, English, French, etc.).
2. Do NOT say "I am an AI assistant" or "As an AI". You ARE the store/owner.
3. Keep it natural for WhatsApp: concise (1-3 sentences) unless answering a specific multi-item inquiry.
4. Maintain a warm, responsive, and commercial demeanor.

Output ONLY the exact text of the reply. Do not wrap in quotes or add notes.
''';

    return await GeminiService.generateText(prompt: prompt, temperature: 0.35);
  }

  static List<String> parseList(String raw) {
    return raw
        .split(RegExp(r'[,\n;]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool matchesEntry({
    required String pattern,
    required String phone,
    required String sender,
    Lead? lead,
  }) {
    final cleaned = pattern.trim().toLowerCase();
    if (cleaned.isEmpty) return false;

    // Check by phone digits if pattern contains digits
    final patternDigits = PhoneUtils.digitsOnly(cleaned);
    final targetDigits = PhoneUtils.digitsOnly(phone);
    if (patternDigits.length >= 6 && targetDigits.length >= 6) {
      if (targetDigits.contains(patternDigits) || patternDigits.contains(targetDigits)) {
        return true;
      }
    }

    // Check by sender or lead name
    final senderLower = sender.toLowerCase().trim();
    final leadNameLower = (lead?.name ?? '').toLowerCase().trim();
    if (senderLower.contains(cleaned) || cleaned.contains(senderLower)) {
      return true;
    }
    if (leadNameLower.isNotEmpty &&
        (leadNameLower.contains(cleaned) || cleaned.contains(leadNameLower))) {
      return true;
    }

    return false;
  }

  /// Determines if an incoming notification matches the user's auto-responder filter rules
  static bool shouldRespond({
    required AutoResponderSettings settings,
    required String sender,
    required String phone,
    Lead? lead,
    String packageName = '',
    bool isGroup = false,
  }) {
    if (!settings.isEnabled) return false;

    // 1. WhatsApp app check (com.whatsapp vs com.whatsapp.w4b vs both)
    if (settings.targetApp == 'com.whatsapp' &&
        packageName.isNotEmpty &&
        packageName != 'com.whatsapp') {
      return false;
    }
    if (settings.targetApp == 'com.whatsapp.w4b' &&
        packageName.isNotEmpty &&
        packageName != 'com.whatsapp.w4b') {
      return false;
    }

    // 2. Group chat check
    if (settings.ignoreGroups && isGroup) {
      return false;
    }

    // 3. Blacklist / Excluded numbers check (always checked first)
    final excludedList = parseList(settings.excludedNumbers);
    for (final excluded in excludedList) {
      if (matchesEntry(pattern: excluded, phone: phone, sender: sender, lead: lead)) {
        return false;
      }
    }

    // 4. Target scope / Respond mode check
    switch (settings.respondMode) {
      case 'unsaved_only':
        if (lead != null && !lead.isUnsaved) return false;
        break;
      case 'saved_only':
        if (lead == null || lead.isUnsaved) return false;
        break;
      case 'specific_list':
        if (lead == null || !lead.isInList(settings.targetAiList)) return false;
        break;
      case 'specific_numbers':
        final whitelist = parseList(settings.whitelistNumbers);
        var matched = false;
        for (final item in whitelist) {
          if (matchesEntry(pattern: item, phone: phone, sender: sender, lead: lead)) {
            matched = true;
            break;
          }
        }
        if (!matched) return false;
        break;
      case 'all':
      default:
        break;
    }

    return true;
  }

  /// Processes an incoming WhatsApp notification, verifies auto-responder rules,
  /// generates the reply with Gemini, and dispatches via Android RemoteInput direct reply.
  static Future<bool> handleIncomingNotification({
    required String notificationKey,
    required String sender,
    required String message,
    required int timestamp,
    String packageName = '',
  }) async {
    final settings = await getSettings();
    if (!settings.isEnabled) return false;

    // Prevent duplicate responses to identical notification triggers
    if (_processedNotificationKeys.contains(notificationKey)) return false;
    _processedNotificationKeys.add(notificationKey);
    if (_processedNotificationKeys.length > 500) {
      _processedNotificationKeys.clear();
    }

    final keyParts = notificationKey.split('|');
    final isGroup = keyParts.length >= 3 &&
        keyParts[1].trim().isNotEmpty &&
        keyParts[2].trim().isNotEmpty &&
        !keyParts[1].trim().toLowerCase().contains(keyParts[2].trim().toLowerCase()) &&
        !keyParts[2].trim().toLowerCase().contains(keyParts[1].trim().toLowerCase());

    final actualPackage = packageName.isNotEmpty
        ? packageName
        : (keyParts.isNotEmpty ? keyParts.first : '');

    try {
      // Find or create the lead in the database
      final phone = DatabaseService.phoneFromSender(sender);
      Lead? lead;
      if (phone.isNotEmpty) {
        lead = await DatabaseService.getLeadByPhone(phone);
      }
      if (lead == null) {
        final leads = await DatabaseService.getLeads(query: sender, limit: 1);
        if (leads.isNotEmpty) lead = leads.first;
      }

      final canRespond = shouldRespond(
        settings: settings,
        sender: sender,
        phone: phone.isNotEmpty ? phone : sender,
        lead: lead,
        packageName: actualPackage,
        isGroup: isGroup,
      );

      if (!canRespond) return false;

      lead ??= await DatabaseService.getOrCreateLead(
        phoneNumber: phone.isNotEmpty ? phone : sender,
        name: sender,
        isUnsaved: true,
        status: 'New',
        notify: true,
      );

      // Add user-defined delay before replying to feel human
      if (settings.delaySeconds > 0) {
        await Future.delayed(Duration(seconds: settings.delaySeconds));
      }

      final history = lead.id != null
          ? await DatabaseService.getMessagesForLead(lead.id!)
          : <LeadMessage>[];

      // Generate contextual reply with Gemini
      final replyText = await generateReply(
        lead: lead,
        incomingMessage: message,
        history: history,
      );

      if (replyText == null || replyText.trim().isEmpty) return false;

      // Send reply via Android Notification Direct Reply (RemoteInput)
      final sent = await WhatsAppService.sendNotificationReply(
        key: notificationKey,
        replyText: replyText.trim(),
      );

      // Record reply in database
      if (lead.id != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await DatabaseService.insertMessage(
          LeadMessage(
            leadId: lead.id!,
            phoneNumber: lead.phoneNumber,
            message: replyText.trim(),
            direction: 'outgoing',
            timestamp: now,
            note: 'Mobi AI Auto-Reply',
          ),
        );
      }

      // Log entry
      final logEntry = AutoResponderLog(
        id: DateTime.now().millisecondsSinceEpoch,
        phoneNumber: lead.phoneNumber,
        senderName: lead.displayName,
        incomingMessage: message,
        replyText: replyText.trim(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        success: sent,
        error: sent ? null : 'RemoteInput reply dispatched (notification shade closed or dispatched)',
      );

      recentLogs.insert(0, logEntry);
      if (recentLogs.length > 50) recentLogs.removeLast();
      logRevision.value++;

      return sent;
    } catch (e) {
      debugPrint('Auto-responder error: $e');
      return false;
    }
  }

  /// Test simulator: simulates how Mobi AI would respond to an arbitrary customer inquiry
  static Future<String?> simulateReply(String testMessage) async {
    final dummyLead = Lead(
      phoneNumber: '+10000000000',
      name: 'Valued Customer',
      status: 'Qualified',
      aiList: 'Customers, Oil Filter Customers',
      aiSummary: 'Frequent customer interested in oil filters and maintenance parts',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      final reply = await generateReply(
        lead: dummyLead,
        incomingMessage: testMessage,
        history: [
          LeadMessage(
            leadId: 0,
            phoneNumber: '+10000000000',
            message: 'Hello, do you have oil filters for Toyota Corolla 2020?',
            direction: 'incoming',
            timestamp: DateTime.now().millisecondsSinceEpoch - 60000,
          ),
        ],
      );
      if (reply != null && reply.isNotEmpty) return reply;
      return 'Hello! Yes, original oil filters for Toyota Corolla 2020 are available. Feel free to stop by or let us know if you need delivery.';
    } catch (e) {
      debugPrint('Simulation note: $e');
      return 'Simulation note: $e';
    }
  }
}
