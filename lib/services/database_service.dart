// lib/services/database_service.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../utils/phone_utils.dart';

class DatabaseService {
  static Database? _db;
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);
  static String? _pendingNotificationSignature;
  static const String _dbName = 'mobiwa_local.db';
  static const int _version = 8;

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
      },
    );
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
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone_number)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_leads_updated ON leads(updated_at DESC)
    ''');

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

  static Future<void> saveWhatsAppDraftQueue({
    required String batchToken,
    required List<int> leadIds,
    required String messageTemplate,
    required int currentIndex,
    required bool awaitingReturn,
  }) async {
    final db = await database;
    await db.insert(
      'whatsapp_draft_queue',
      {
        'id': 1,
        'batch_token': batchToken,
        'lead_ids_json': jsonEncode(leadIds),
        'message_template': messageTemplate,
        'current_index': currentIndex,
        'awaiting_return': awaitingReturn ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, Object?>?> getWhatsAppDraftQueue() async {
    final db = await database;
    final rows = await db.query(
      'whatsapp_draft_queue',
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  static Future<void> clearWhatsAppDraftQueue() async {
    final db = await database;
    await db.delete('whatsapp_draft_queue', where: 'id = 1');
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
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (query != null && query.trim().isNotEmpty) {
      final term = '%${query.trim()}%';
      whereClauses.add(
          '(l.name LIKE ? OR l.phone_number LIKE ? OR l.notes LIKE ? OR l.tags LIKE ?)');
      whereArgs.addAll([term, term, term, term]);
    }

    if (status != null && status.isNotEmpty && status != 'All') {
      whereClauses.add('l.status = ?');
      whereArgs.add(status);
    }

    if (onlyUnsaved == true) {
      whereClauses.add('l.is_unsaved = 1');
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

  /// Imports exported chat messages for an explicitly selected lead. A stable
  /// per-message key prevents importing the same export more than once.
  static Future<int> importWhatsAppExportMessages(
    int leadId,
    List<({String sender, String text, String direction, int timestamp})>
        messages,
  ) async {
    if (messages.isEmpty) return 0;
    final db = await database;
    final leadRows = await db.query(
      'leads',
      columns: ['phone_number'],
      where: 'id = ?',
      whereArgs: [leadId],
      limit: 1,
    );
    if (leadRows.isEmpty) return 0;
    final phone = leadRows.first['phone_number']?.toString() ?? '';
    var inserted = 0;

    await db.transaction((txn) async {
      for (final message in messages) {
        final sourceKey = _exportSourceKey(leadId, message);
        final id = await txn.insert(
          'messages',
          {
            'lead_id': leadId,
            'phone_number': phone,
            'message': message.text,
            'direction': message.direction,
            'timestamp': message.timestamp,
            'note': 'Imported WhatsApp export • ${message.sender}',
            'source_key': sourceKey,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id != -1) inserted++;
      }
      if (inserted > 0) {
        final newestTimestamp = messages
            .map((message) => message.timestamp)
            .reduce((a, b) => a > b ? a : b);
        await txn.update(
          'leads',
          {'updated_at': newestTimestamp},
          where: 'id = ? AND updated_at < ?',
          whereArgs: [leadId, newestTimestamp],
        );
      }
    });

    if (inserted > 0) notifyDataChanged();
    return inserted;
  }

  static String _exportSourceKey(
    int leadId,
    ({String sender, String text, String direction, int timestamp}) message,
  ) {
    final input = '$leadId|${message.timestamp}|${message.direction}|'
        '${message.sender}|${message.text}';
    var hash = 0xcbf29ce484222325;
    for (final byte in input.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'wa-export:${hash.toRadixString(16)}';
  }

  /// Converts notification previews into messages once a sender can be matched
  /// to a phone number or a unique device contact.
  static Future<Map<String, int>> processPendingNotifications() async {
    final db = await database;
    var importedMessages = 0;
    var importedLeads = 0;
    var pendingQueueChanged = false;
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
          // A display name with multiple numbers is ambiguous; retain it for a
          // later contact sync or for the user to resolve by adding a number.
          if (uniqueNumbers.length != 1) continue;
          phone = uniqueNumbers.single;
          cachedContact = matches;
        }
        if (!PhoneUtils.looksLikePhoneNumber(phone)) continue;
        final digits = PhoneUtils.digitsOnly(phone);
        final phoneCandidates = <String>{phone, digits, '+$digits'}.toList();
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
        if (insertedId != -1) importedMessages++;
        await txn.update('leads', {'updated_at': timestamp},
            where: 'id = ? AND updated_at < ?', whereArgs: [leadId, timestamp]);
        await txn.delete('pending_notifications',
            where: 'notification_key = ?', whereArgs: [key]);
      }
    });

    if (importedMessages > 0 || importedLeads > 0 || pendingQueueChanged) {
      notifyDataChanged();
    }

    return {'leads': importedLeads, 'messages': importedMessages};
  }

  static Future<List<Map<String, Object?>>> getPendingNotifications(
      {int limit = 500}) async {
    final db = await database;
    return db.query(
      'pending_notifications',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Links a preview that could not be matched automatically to a lead chosen
  /// by the user, then removes it from the unresolved queue.
  static Future<bool> assignPendingNotificationToLead(
    String notificationKey,
    int leadId,
  ) async {
    final db = await database;
    var assigned = false;
    await db.transaction((txn) async {
      final pending = await txn.query(
        'pending_notifications',
        where: 'notification_key = ?',
        whereArgs: [notificationKey],
        limit: 1,
      );
      if (pending.isEmpty) return;
      final leads = await txn.query(
        'leads',
        columns: ['phone_number'],
        where: 'id = ?',
        whereArgs: [leadId],
        limit: 1,
      );
      if (leads.isEmpty) return;

      final notification = pending.single;
      final phone = leads.single['phone_number']?.toString() ?? '';
      final sender = notification['sender']?.toString() ?? '';
      final timestamp = notification['timestamp'] as int? ?? 0;
      final message = notification['message']?.toString() ?? '';
      final id = await txn.insert(
        'messages',
        {
          'lead_id': leadId,
          'phone_number': phone,
          'message': message,
          'direction': 'incoming',
          'timestamp': timestamp,
          'note': 'Sender matched manually: $sender',
          'source_key': notificationKey,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (id != -1) {
        await txn.update(
          'leads',
          {'updated_at': timestamp},
          where: 'id = ? AND updated_at < ?',
          whereArgs: [leadId, timestamp],
        );
      }
      await txn.delete(
        'pending_notifications',
        where: 'notification_key = ?',
        whereArgs: [notificationKey],
      );
      assigned = true;
    });
    if (assigned) notifyDataChanged();
    return assigned;
  }

  static String _phoneFromSender(String sender) {
    final match = RegExp(r'\+?\d[\d\s().-]{5,}\d').firstMatch(sender);
    if (match == null) return '';
    final candidate = PhoneUtils.normalize(match.group(0)!);
    return PhoneUtils.looksLikePhoneNumber(candidate) ? candidate : '';
  }

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
