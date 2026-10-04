// lib/services/database_service.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../utils/phone_utils.dart';
import 'auto_responder_service.dart';
import 'whatsapp_service.dart';

class DatabaseService {
  static Database? _db;
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);
  static String? _pendingNotificationSignature;
  static Timer? _notificationWorkerTimer;
  static bool _isProcessingNotifications = false;
  static const String _dbName = 'mobiwa_local.db';
  static const int _version = 9;

  /// Allows setting a mock/in-memory database instance for testing
  static void setDatabaseForTesting(Database? db) {
    _db = db;
  }

  static void notifyDataChanged() => dataRevision.value++;

  static Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await _createTables(db);
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_source_key
          ON messages(source_key)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTables(db);
        }
        if (oldVersion < 3) {
          final messageColumns =
              await db.rawQuery('PRAGMA table_info(messages)');
          if (!messageColumns.any((column) => column['name'] == 'source_key')) {
            await db.execute('ALTER TABLE messages ADD COLUMN source_key TEXT');
          }
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_source_key
            ON messages(source_key)
          ''');
        }
        if (oldVersion < 4) {
          await _createPendingNotificationsTable(db);
        }
        if (oldVersion < 5) {
          final leadColumns = await db.rawQuery('PRAGMA table_info(leads)');
          if (!leadColumns
              .any((column) => column['name'] == 'whatsapp_opt_in')) {
            await db.execute(
                'ALTER TABLE leads ADD COLUMN whatsapp_opt_in INTEGER NOT NULL DEFAULT 0');
          }
          if (!leadColumns.any(
              (column) => column['name'] == 'whatsapp_consent_updated_at')) {
            await db.execute(
                'ALTER TABLE leads ADD COLUMN whatsapp_consent_updated_at INTEGER');
          }
        }
        if (oldVersion < 6) {
          await _createWhatsAppConsentEventsTable(db);
        }
        if (oldVersion < 7) {
          await _createWhatsAppDraftQueueTable(db);
        }
        if (oldVersion < 8) {
          await _createAppPreferencesTable(db);
        }
        if (oldVersion < 9) {
          await _addMobiAiColumns(db);
        }
      },
    );
  }

  static Future<void> _addMobiAiColumns(DatabaseExecutor db) async {
    final leadColumns = await db.rawQuery('PRAGMA table_info(leads)');
    final names = leadColumns.map((c) => c['name']).toSet();
    if (!names.contains('ai_list')) {
      await db.execute("ALTER TABLE leads ADD COLUMN ai_list TEXT DEFAULT ''");
    }
    if (!names.contains('ai_summary')) {
      await db.execute("ALTER TABLE leads ADD COLUMN ai_summary TEXT DEFAULT ''");
    }
    if (!names.contains('ai_next_action')) {
      await db.execute(
          "ALTER TABLE leads ADD COLUMN ai_next_action TEXT DEFAULT ''");
    }
    if (!names.contains('ai_analyzed_at')) {
      await db.execute('ALTER TABLE leads ADD COLUMN ai_analyzed_at INTEGER');
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_leads_ai_list ON leads(ai_list)');
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS leads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phone_number TEXT NOT NULL UNIQUE,
        name TEXT,
        notes TEXT,
        status TEXT DEFAULT 'New',
        is_unsaved INTEGER DEFAULT 1,
        tags TEXT,
        whatsapp_opt_in INTEGER NOT NULL DEFAULT 0,
        whatsapp_consent_updated_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        ai_list TEXT DEFAULT '',
        ai_summary TEXT DEFAULT '',
        ai_next_action TEXT DEFAULT '',
        ai_analyzed_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone_number)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_leads_updated ON leads(updated_at DESC)
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_leads_ai_list ON leads(ai_list)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lead_id INTEGER NOT NULL,
        phone_number TEXT NOT NULL,
        message TEXT NOT NULL,
        direction TEXT DEFAULT 'incoming',
        timestamp INTEGER NOT NULL,
        note TEXT,
        source_key TEXT,
        FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_lead ON messages(lead_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(timestamp DESC)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_source_key
      ON messages(source_key)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts_cache (
        normalized_phone TEXT PRIMARY KEY,
        display_name TEXT,
        synced_at INTEGER
      )
    ''');
    await _createPendingNotificationsTable(db);
    await _createWhatsAppConsentEventsTable(db);
    await _createWhatsAppDraftQueueTable(db);
    await _createAppPreferencesTable(db);
  }

  static Future<void> _createWhatsAppConsentEventsTable(
      DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS whatsapp_consent_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lead_id INTEGER NOT NULL,
        opted_in INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createPendingNotificationsTable(
      DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_notifications (
        notification_key TEXT PRIMARY KEY,
        package_name TEXT NOT NULL,
        sender TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createWhatsAppDraftQueueTable(
      DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS whatsapp_draft_queue (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        batch_token TEXT NOT NULL,
        lead_ids_json TEXT NOT NULL,
        message_template TEXT NOT NULL,
        current_index INTEGER NOT NULL DEFAULT 0,
        awaiting_return INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createAppPreferencesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_preferences (
        preference_key TEXT PRIMARY KEY,
        preference_value TEXT NOT NULL
      )
    ''');
  }

  static Future<bool> isAutomaticContactImportEnabled() async {
    final db = await database;
    final rows = await db.query(
      'app_preferences',
      columns: ['preference_value'],
      where: 'preference_key = ?',
      whereArgs: ['automatic_contact_import'],
      limit: 1,
    );
    return rows.isEmpty || rows.single['preference_value'] == '1';
  }

  static Future<void> setAutoImportContactsEnabled(bool enabled) async {
    final db = await database;
    await db.insert(
      'app_preferences',
      {
        'preference_key': 'automatic_contact_import',
        'preference_value': enabled ? '1' : '0',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }



  // --- Lead Operations ---

  /// Insert or get existing lead by phone number
  static Future<Lead> getOrCreateLead({
    required String phoneNumber,
    String name = '',
    String notes = '',
    String tags = '',
    String? status,
    bool? isUnsaved,
    bool whatsappOptIn = false,
    bool notify = true,
  }) async {
    final db = await database;
    final normalized = PhoneUtils.normalize(phoneNumber);
    if (!PhoneUtils.looksLikePhoneNumber(normalized)) {
      throw ArgumentError.value(
          phoneNumber, 'phoneNumber', 'Enter a valid phone number.');
    }

    final existing = await getLeadByPhone(normalized);
    if (existing != null) {
      final updated = existing.copyWith(
        name: name.trim().isNotEmpty ? name.trim() : null,
        notes: notes.trim().isNotEmpty ? notes.trim() : null,
        tags: tags.trim().isNotEmpty ? tags.trim() : null,
        status: status,
        isUnsaved: isUnsaved,
        whatsappOptIn: whatsappOptIn || existing.whatsappOptIn,
      );
      if (updated.name != existing.name ||
          updated.notes != existing.notes ||
          updated.tags != existing.tags ||
          updated.status != existing.status ||
          updated.isUnsaved != existing.isUnsaved ||
          updated.whatsappOptIn != existing.whatsappOptIn) {
        await updateLead(updated, notify: notify);
        return updated.copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lead = Lead(
      phoneNumber: normalized,
      name: name,
      notes: notes,
      tags: tags,
      status: status ?? 'New',
      isUnsaved: isUnsaved ?? true,
      whatsappOptIn: whatsappOptIn,
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('leads', lead.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != -1) {
      if (notify) notifyDataChanged();
      return lead.copyWith(id: id);
    }
    return (await getLeadByPhone(normalized)) ?? lead;
  }

  static Future<int> insertLead(Lead lead) async {
    final db = await database;
    final id = await db.insert('leads', lead.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDataChanged();
    return id;
  }

  static Future<int> updateLead(Lead lead, {bool notify = true}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = lead.toMap()..['updated_at'] = now;
    final count = await db.update(
      'leads',
      map,
      where: 'id = ?',
      whereArgs: [lead.id],
    );
    if (notify && count > 0) notifyDataChanged();
    return count;
  }

  static Future<void> setWhatsAppOptIn(int leadId, bool optedIn) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
        'leads',
        {
          'whatsapp_opt_in': optedIn ? 1 : 0,
          'whatsapp_consent_updated_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [leadId],
      );
      await txn.insert('whatsapp_consent_events', {
        'lead_id': leadId,
        'opted_in': optedIn ? 1 : 0,
        'timestamp': now,
        'source': 'manual',
      });
    });
    notifyDataChanged();
  }

  static Future<int> deleteLead(int id) async {
    final db = await database;
    await db.delete('messages', where: 'lead_id = ?', whereArgs: [id]);
    await db.delete('whatsapp_consent_events',
        where: 'lead_id = ?', whereArgs: [id]);
    final count = await db.delete('leads', where: 'id = ?', whereArgs: [id]);
    if (count > 0) notifyDataChanged();
    return count;
  }

  static Future<Lead?> getLeadById(int id) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM messages m WHERE m.lead_id = l.id) as message_count,
        (SELECT message FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message,
        (SELECT timestamp FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message_time
      FROM leads l
      WHERE l.id = ?
    ''', [id]);

    if (results.isEmpty) return null;
    return Lead.fromMap(results.first);
  }

  static Future<Lead?> getLeadByPhone(String phone) async {
    final db = await database;
    final normalized = PhoneUtils.normalize(phone);
    final digits = PhoneUtils.digitsOnly(normalized);
    final candidates = <String>{
      normalized,
      digits,
      '+$digits',
      ...PhoneUtils.getVariants(digits),
    }.where((value) => value.isNotEmpty).toList();
    final results = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM messages m WHERE m.lead_id = l.id) as message_count,
        (SELECT message FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message,
        (SELECT timestamp FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message_time
      FROM leads l
      WHERE l.phone_number IN (${List.filled(candidates.length, '?').join(',')})
      ORDER BY CASE WHEN l.phone_number = ? THEN 0 ELSE 1 END
      LIMIT 1
    ''', [...candidates, normalized]);

    if (results.isEmpty) return null;
    return Lead.fromMap(results.first);
  }

  /// Get leads with flexible search, status filtering, and unsaved sorting
  static Future<List<Lead>> getLeads({
    String? query,
    String? status,
    bool? onlyUnsaved,
    String? aiList,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (query != null && query.trim().isNotEmpty) {
      final term = '%${query.trim()}%';
      whereClauses.add(
          '(l.name LIKE ? OR l.phone_number LIKE ? OR l.notes LIKE ? OR l.tags LIKE ? OR l.ai_summary LIKE ?)');
      whereArgs.addAll([term, term, term, term, term]);
    }

    if (status != null && status.isNotEmpty && status != 'All') {
      whereClauses.add('l.status = ?');
      whereArgs.add(status);
    }

    if (onlyUnsaved == true) {
      whereClauses.add('l.is_unsaved = 1');
    }

    if (aiList != null && aiList.isNotEmpty) {
      whereClauses.add(
          "(l.ai_list = ? OR l.ai_list LIKE ? OR l.ai_list LIKE ? OR l.ai_list LIKE ?)");
      whereArgs.addAll([
        aiList,
        '$aiList,%',
        '%, $aiList,%',
        '%, $aiList',
      ]);
    }

    final whereSql =
        whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final sql = '''
      SELECT l.*,
        (SELECT COUNT(*) FROM messages m WHERE m.lead_id = l.id) as message_count,
        (SELECT message FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message,
        (SELECT timestamp FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message_time
      FROM leads l
      $whereSql
      ORDER BY l.updated_at DESC
      LIMIT ? OFFSET ?
    ''';

    whereArgs.add(limit);
    whereArgs.add(offset);

    final results = await db.rawQuery(sql, whereArgs);
    return results.map(Lead.fromMap).toList();
  }

  // --- Mobi AI CRM lists ---

  /// Dynamic counts of customers across all unique AI & product lists.
  /// (Each customer can belong to multiple lists, e.g. "Customers" & "Oil Filter Customers")
  static Future<Map<String, int>> getAiListCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ai_list FROM leads
      WHERE ai_list IS NOT NULL AND ai_list != ''
    ''');
    final counts = <String, int>{};
    for (final r in rows) {
      final raw = r['ai_list']?.toString() ?? '';
      final lists = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      for (final l in lists) {
        counts[l] = (counts[l] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Returns all active AI & product lists discovered across leads, sorted by member count.
  static Future<List<String>> getAllAiLists() async {
    final counts = await getAiListCounts();
    final list = counts.keys.toList();
    list.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    return list;
  }

  /// Leads Mobi AI should look at: unsaved numbers and anyone with chat
  /// history. Saved phone-book contacts without any chat are skipped so the
  /// AI does not open hundreds of empty WhatsApp chats.
  static Future<List<Lead>> getMobiAiCandidates({
    bool onlyUnanalyzed = true,
    bool onlyUnsaved = false,
    int limit = 500,
  }) async {
    final db = await database;
    final where = <String>[
      onlyUnsaved
          ? 'l.is_unsaved = 1'
          : '(l.is_unsaved = 1 OR EXISTS (SELECT 1 FROM messages m WHERE m.lead_id = l.id))',
      if (onlyUnanalyzed) "(l.ai_list IS NULL OR l.ai_list = '')",
    ];
    final rows = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM messages m WHERE m.lead_id = l.id) as message_count,
        (SELECT message FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message,
        (SELECT timestamp FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message_time
      FROM leads l
      WHERE ${where.join(' AND ')}
      ORDER BY l.updated_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Lead.fromMap).toList();
  }

  /// Sets or updates a customer's Mobi AI lists (comma-separated).
  static Future<void> setLeadAiList(int leadId, String aiList) async {
    final db = await database;
    await db.update(
      'leads',
      {
        'ai_list': aiList,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [leadId],
    );
    notifyDataChanged();
  }

  /// Adds a lead to an additional list (e.g. "Oil Filter Customers")
  static Future<void> addLeadToList(int leadId, String listName) async {
    final lead = await getLeadById(leadId);
    if (lead == null) return;
    final current = lead.aiLists.toSet();
    current.add(listName.trim());
    await setLeadAiList(leadId, current.join(', '));
  }

  /// Removes a lead from a specific list
  static Future<void> removeLeadFromList(int leadId, String listName) async {
    final lead = await getLeadById(leadId);
    if (lead == null) return;
    final current = lead.aiLists.toSet();
    current.removeWhere((l) => l.toLowerCase() == listName.trim().toLowerCase());
    await setLeadAiList(leadId, current.join(', '));
  }

  /// Stores messages read from the WhatsApp chat screen. Re-reading the same
  /// chat does not create duplicates (stable per-message source key).
  static Future<int> insertScrapedMessages(
    int leadId,
    String phone,
    List<Map<String, String>> scraped,
  ) async {
    if (scraped.isEmpty) return 0;
    final db = await database;
    var inserted = 0;
    var newest = 0;
    await db.transaction((txn) async {
      for (final item in scraped) {
        final text = (item['message'] ?? '').trim();
        if (text.isEmpty) continue;
        final direction = item['direction'] == 'outgoing' ? 'outgoing' : 'incoming';
        final time = item['time'] ?? '';
        final ts = int.tryParse(item['timestamp'] ?? '') ??
            DateTime.now().millisecondsSinceEpoch;
        final sourceKey = _scrapeSourceKey(leadId, direction, time, text);
        final existing = await txn.rawQuery(
          'SELECT 1 FROM messages WHERE source_key = ? LIMIT 1',
          [sourceKey],
        );
        if (existing.isNotEmpty) continue;
        final id = await txn.insert(
          'messages',
          {
            'lead_id': leadId,
            'phone_number': phone,
            'message': text,
            'direction': direction,
            'timestamp': ts,
            'note': time.isEmpty ? 'Read by Mobi AI' : 'Read by Mobi AI • $time',
            'source_key': sourceKey,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) {
          inserted++;
          if (ts > newest) newest = ts;
        }
      }
      if (inserted > 0) {
        await txn.update(
          'leads',
          {'updated_at': newest},
          where: 'id = ? AND updated_at < ?',
          whereArgs: [leadId, newest],
        );
      }
    });
    if (inserted > 0) notifyDataChanged();
    return inserted;
  }

  static String _scrapeSourceKey(
      int leadId, String direction, String time, String text) {
    final input = '$leadId|$direction|$time|$text';
    var hash = 0xcbf29ce484222325;
    for (final byte in input.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'wa-read:${hash.toRadixString(16)}';
  }

  // --- Message Operations ---

  static Future<int> insertMessage(LeadMessage message) async {
    final db = await database;
    final id = await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // A source key makes retried imports and a recovered bulk-send queue
    // idempotent. Do not update the lead or refresh screens for a duplicate.
    if (id != -1) {
      await db.update(
        'leads',
        {'updated_at': message.timestamp},
        where: 'id = ?',
        whereArgs: [message.leadId],
      );
      notifyDataChanged();
    }
    return id;
  }



  /// Starts background notification processing: listens for real-time notification events
  /// from Android and maintains a lightweight periodic fallback worker.
  static void startNotificationWorker() {
    WhatsAppService.registerNotificationListener(() {
      unawaited(processPendingNotifications());
    });

    _notificationWorkerTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(processPendingNotifications()),
    );

    unawaited(processPendingNotifications());
  }

  /// Converts notification previews into messages once a sender can be matched
  /// to a phone number or a unique device contact.
  static Future<Map<String, int>> processPendingNotifications() async {
    if (_isProcessingNotifications) return {'leads': 0, 'messages': 0};
    _isProcessingNotifications = true;

    try {
      final db = await database;
      var importedMessages = 0;
      var importedLeads = 0;
      var pendingQueueChanged = false;
      final toAutoRespond = <Map<String, dynamic>>[];
      await db.transaction((txn) async {
        final pending =
            await txn.query('pending_notifications', orderBy: 'timestamp ASC');
        final signature = pending
            .map((row) => row['notification_key']?.toString() ?? '')
            .join('|');
        pendingQueueChanged = signature != _pendingNotificationSignature;
        _pendingNotificationSignature = signature;
        for (final notification in pending) {
          final key = notification['notification_key']?.toString() ?? '';
          final sender = notification['sender']?.toString().trim() ?? '';
          final body = notification['message']?.toString().trim() ?? '';
          final timestamp = notification['timestamp'];
          if (key.isEmpty ||
              sender.isEmpty ||
              body.isEmpty ||
              timestamp is! int ||
              timestamp <= 0) {
            continue;
          }

          var phone = _phoneFromSender(sender);
          var cachedContact = <Map<String, Object?>>[];
          if (phone.isNotEmpty) {
            final variants = PhoneUtils.getVariants(phone).toList();
            cachedContact = await txn.query(
              'contacts_cache',
              columns: ['normalized_phone', 'display_name'],
              where:
                  'normalized_phone IN (${List.filled(variants.length, '?').join(',')})',
              whereArgs: variants,
            );
          } else {
            final matches = await txn.query(
              'contacts_cache',
              columns: ['normalized_phone', 'display_name'],
              where: 'LOWER(TRIM(display_name)) = ?',
              whereArgs: [sender.toLowerCase()],
            );
            final matchedNumbers = matches
                .map((row) => PhoneUtils.normalize(
                    row['normalized_phone']?.toString() ?? ''))
                .where(PhoneUtils.looksLikePhoneNumber)
                .toSet();
            final uniqueNumbers = _collapsePhoneVariants(matchedNumbers);
            if (uniqueNumbers.length == 1) {
              phone = uniqueNumbers.single;
              cachedContact = matches;
            } else {
              // Try matching an existing lead by exact name
              final existingByName = await txn.query(
                'leads',
                columns: ['phone_number'],
                where: 'LOWER(TRIM(name)) = ?',
                whereArgs: [sender.toLowerCase()],
                limit: 1,
              );
              if (existingByName.isNotEmpty) {
                phone = existingByName.first['phone_number']?.toString() ?? '';
              } else {
                // If not found in contacts or leads, use the sender name as a fallback identifier
                phone = sender;
              }
            }
          }
          if (phone.isEmpty) continue;
          final digits = PhoneUtils.digitsOnly(phone);
          final phoneCandidates = <String>{
            phone,
            if (PhoneUtils.looksLikePhoneNumber(phone) && digits.isNotEmpty) ...[
              digits,
              '+$digits',
            ],
          }.toList();
          final matchedNames = cachedContact
              .map((row) => row['display_name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet();
          final matchedContactName =
              matchedNames.length == 1 ? matchedNames.single : '';
          final importedName =
              matchedContactName.isNotEmpty ? matchedContactName : sender;

          final existing = await txn.query(
            'leads',
            columns: ['id', 'name'],
            where:
                'phone_number IN (${List.filled(phoneCandidates.length, '?').join(',')})',
            whereArgs: phoneCandidates,
            limit: 1,
          );
          late final int leadId;
          if (existing.isEmpty) {
            final now = DateTime.now().millisecondsSinceEpoch;
            leadId = await txn.insert('leads', {
              'phone_number': phone,
              'name': importedName,
              'notes': '',
              'status': 'New',
              'is_unsaved': cachedContact.isEmpty ? 1 : 0,
              'tags': '',
              'created_at': now,
              'updated_at': now,
            });
            importedLeads++;
          } else {
            leadId = existing.first['id'] as int;
            final oldName = existing.first['name']?.toString() ?? '';
            final updates = <String, Object?>{};
            if (oldName.isEmpty && importedName.isNotEmpty) {
              updates['name'] = importedName;
            }
            if (cachedContact.isNotEmpty) {
              updates['is_unsaved'] = 0;
            }
            if (updates.isNotEmpty) {
              await txn
                  .update('leads', updates, where: 'id = ?', whereArgs: [leadId]);
            }
          }

          final insertedId = await txn.insert(
              'messages',
              {
                'lead_id': leadId,
                'phone_number': phone,
                'message': body,
                'direction': 'incoming',
                'timestamp': timestamp,
                'note': '',
                'source_key': key,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          if (insertedId != -1) {
            importedMessages++;
            toAutoRespond.add({
              'key': key,
              'sender': sender,
              'message': body,
              'timestamp': timestamp,
              'packageName': notification['package_name']?.toString() ?? '',
            });
          }
          await txn.update('leads', {'updated_at': timestamp},
              where: 'id = ? AND updated_at < ?', whereArgs: [leadId, timestamp]);
          await txn.delete('pending_notifications',
              where: 'notification_key = ?', whereArgs: [key]);
        }
      });

      if (importedMessages > 0 || importedLeads > 0 || pendingQueueChanged) {
        notifyDataChanged();
      }

      // Trigger AI Auto-Responder in background for new messages
      for (final item in toAutoRespond) {
        unawaited(
          AutoResponderService.handleIncomingNotification(
            notificationKey: item['key'] as String,
            sender: item['sender'] as String,
            message: item['message'] as String,
            timestamp: item['timestamp'] as int,
            packageName: item['packageName'] as String? ?? '',
          ),
        );
      }

      return {'leads': importedLeads, 'messages': importedMessages};
    } finally {
      _isProcessingNotifications = false;
    }
  }



  static String phoneFromSender(String sender) {
    final match = RegExp(r'\+?\d[\d\s().-]{5,}\d').firstMatch(sender);
    if (match == null) return '';
    final candidate = PhoneUtils.normalize(match.group(0)!);
    return PhoneUtils.looksLikePhoneNumber(candidate) ? candidate : '';
  }

  static String _phoneFromSender(String sender) => phoneFromSender(sender);

  static Set<String> _collapsePhoneVariants(Set<String> numbers) {
    final remaining = numbers.toSet();
    final representatives = <String>{};
    while (remaining.isNotEmpty) {
      final seed = remaining.first;
      final group = remaining
          .where((number) => PhoneUtils.getVariants(seed)
              .intersection(PhoneUtils.getVariants(number))
              .isNotEmpty)
          .toSet();
      final candidates = group.isEmpty ? {seed} : group;
      representatives.add(candidates.reduce((a, b) =>
          PhoneUtils.digitsOnly(a).length >= PhoneUtils.digitsOnly(b).length
              ? a
              : b));
      remaining.removeAll(candidates);
    }
    return representatives;
  }

  static Future<List<LeadMessage>> getMessagesForLead(int leadId) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: 'lead_id = ?',
      whereArgs: [leadId],
      orderBy: 'timestamp ASC',
    );
    return results.map(LeadMessage.fromMap).toList();
  }

  /// Returns the most recently recorded messages for the global activity feed.
  static Future<List<LeadMessage>> getRecentMessages({
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await database;
    final results = await db.query(
      'messages',
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return results.map(LeadMessage.fromMap).toList();
  }

  static Future<List<Map<String, Object?>>> getAllMessagesForExport() async {
    final db = await database;
    return db.rawQuery('''
      SELECT m.id, m.phone_number, m.message, m.direction, m.timestamp,
        m.note, m.source_key, COALESCE(l.name, '') AS lead_name
      FROM messages m
      LEFT JOIN leads l ON l.id = m.lead_id
      ORDER BY m.timestamp ASC, m.id ASC
    ''');
  }

  static Future<List<LeadMessage>> searchMessages(String query,
      {int limit = 100, int offset = 0}) async {
    final db = await database;
    final term = '%${query.trim()}%';
    final results = await db.query(
      'messages',
      where: 'message LIKE ? OR note LIKE ? OR phone_number LIKE ?',
      whereArgs: [term, term, term],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return results.map(LeadMessage.fromMap).toList();
  }

  static Future<int> deleteMessage(int id) async {
    final db = await database;
    final deleted =
        await db.delete('messages', where: 'id = ?', whereArgs: [id]);
    if (deleted > 0) notifyDataChanged();
    return deleted;
  }

  // --- Contacts Synchronization Cache ---

  static Future<void> syncContactsCache(Map<String, String> contactsMap) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Clear old cache before replacing
    batch.delete('contacts_cache');

    for (final entry in contactsMap.entries) {
      batch.insert(
        'contacts_cache',
        {
          'normalized_phone': entry.key,
          'display_name': entry.value,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.insert(
      'app_preferences',
      {
        'preference_key': 'last_contacts_sync_at',
        'preference_value': now.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
    notifyDataChanged();
  }

  static Future<Map<String, int?>> getContactsSyncInfo() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM contacts_cache')) ??
        0;
    final rows = await db.query(
      'app_preferences',
      columns: ['preference_value'],
      where: 'preference_key = ?',
      whereArgs: ['last_contacts_sync_at'],
      limit: 1,
    );
    final lastSync = rows.isEmpty
        ? null
        : int.tryParse(rows.single['preference_value']?.toString() ?? '');
    return {'count': count, 'lastSyncAt': lastSync};
  }

  static Future<void> updateLeadClassification(int id, bool isUnsaved,
      {String? contactName}) async {
    final db = await database;
    final values = <String, dynamic>{
      'is_unsaved': isUnsaved ? 1 : 0,
    };
    if (contactName != null && contactName.isNotEmpty) {
      values['name'] = contactName;
    }
    await db.update('leads', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> batchUpdateLeadClassification(
      List<Map<String, dynamic>> updates) async {
    if (updates.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final update in updates) {
      final id = update['id'] as int;
      final values = Map<String, dynamic>.from(update)..remove('id');
      batch.update('leads', values, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    notifyDataChanged();
  }

  static Future<Set<String>> getAllLeadPhoneNumbers() async {
    final db = await database;
    final rows = await db.query('leads', columns: ['phone_number']);
    return rows.map((r) => r['phone_number'] as String).toSet();
  }

  static Future<int> batchInsertContactsAsLeads(
      List<Map<String, dynamic>> leadData) async {
    if (leadData.isEmpty) return 0;
    final db = await database;
    final batch = db.batch();
    for (final data in leadData) {
      batch.insert(
        'leads',
        data,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    notifyDataChanged();
    return leadData.length;
  }

  // --- Statistics & Overview ---

  static Future<Map<String, int>> getStats() async {
    final db = await database;

    final totalLeads = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM leads')) ??
        0;

    final unsavedLeads = Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM leads WHERE is_unsaved = 1')) ??
        0;

    final totalMessages = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM messages')) ??
        0;

    final unmatchedNotifications = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pending_notifications')) ??
        0;

    final now = DateTime.now();
    final startOfToday =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    final recentActivity = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM leads WHERE updated_at >= ?',
            [startOfToday])) ??
        0;

    return {
      'totalLeads': totalLeads,
      'unsavedLeads': unsavedLeads,
      'totalMessages': totalMessages,
      'unmatchedNotifications': unmatchedNotifications,
      'recentActivity': recentActivity,
    };
  }

  // --- Data Management ---

  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('leads');
    await db.delete('contacts_cache');
    await db.delete('pending_notifications');
    await db.delete('whatsapp_consent_events');
    await db.delete('whatsapp_draft_queue');
    await db.delete('app_preferences',
        where: 'preference_key = ?', whereArgs: ['last_contacts_sync_at']);
    await db.insert(
      'app_preferences',
      {
        'preference_key': 'automatic_contact_import',
        'preference_value': '0',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyDataChanged();
  }
}
