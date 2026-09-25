// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../utils/phone_utils.dart';

class DatabaseService {
  static Database? _db;
  static const String _dbName = 'mobiwa_local.db';
  static const int _version = 2;

  /// Allows setting a mock/in-memory database instance for testing
  static void setDatabaseForTesting(Database? db) {
    _db = db;
  }

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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTables(db);
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
  }

  // --- Lead Operations ---

  /// Insert or get existing lead by phone number
  static Future<Lead> getOrCreateLead({
    required String phoneNumber,
    String name = '',
    String notes = '',
    String status = 'New',
    bool isUnsaved = true,
  }) async {
    final db = await database;
    final normalized = PhoneUtils.normalize(phoneNumber);

    final existing = await getLeadByPhone(normalized);
    if (existing != null) {
      if (name.isNotEmpty && existing.name.isEmpty) {
        final updated = existing.copyWith(
          name: name,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await updateLead(updated);
        return updated;
      }
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lead = Lead(
      phoneNumber: normalized,
      name: name,
      notes: notes,
      status: status,
      isUnsaved: isUnsaved,
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('leads', lead.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return lead.copyWith(id: id);
  }

  static Future<int> insertLead(Lead lead) async {
    final db = await database;
    return await db.insert('leads', lead.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> updateLead(Lead lead) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = lead.toMap()..['updated_at'] = now;
    return await db.update(
      'leads',
      map,
      where: 'id = ?',
      whereArgs: [lead.id],
    );
  }

  static Future<int> deleteLead(int id) async {
    final db = await database;
    await db.delete('messages', where: 'lead_id = ?', whereArgs: [id]);
    return await db.delete('leads', where: 'id = ?', whereArgs: [id]);
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
    final results = await db.rawQuery('''
      SELECT l.*,
        (SELECT COUNT(*) FROM messages m WHERE m.lead_id = l.id) as message_count,
        (SELECT message FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message,
        (SELECT timestamp FROM messages m WHERE m.lead_id = l.id ORDER BY timestamp DESC LIMIT 1) as last_message_time
      FROM leads l
      WHERE l.phone_number = ?
    ''', [normalized]);

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
      whereClauses.add('(l.name LIKE ? OR l.phone_number LIKE ? OR l.notes LIKE ? OR l.tags LIKE ?)');
      whereArgs.addAll([term, term, term, term]);
    }

    if (status != null && status.isNotEmpty && status != 'All') {
      whereClauses.add('l.status = ?');
      whereArgs.add(status);
    }

    if (onlyUnsaved == true) {
      whereClauses.add('l.is_unsaved = 1');
    }

    final whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

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
    final id = await db.insert('messages', message.toMap());

    // Update lead's updated_at timestamp
    await db.update(
      'leads',
      {'updated_at': message.timestamp},
      where: 'id = ?',
      whereArgs: [message.leadId],
    );
    return id;
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

  static Future<List<LeadMessage>> searchMessages(String query, {int limit = 100}) async {
    final db = await database;
    final term = '%${query.trim()}%';
    final results = await db.query(
      'messages',
      where: 'message LIKE ? OR note LIKE ? OR phone_number LIKE ?',
      whereArgs: [term, term, term],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return results.map(LeadMessage.fromMap).toList();
  }

  static Future<int> deleteMessage(int id) async {
    final db = await database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [id]);
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
    await batch.commit(noResult: true);
  }

  static Future<void> updateLeadClassification(
      int id, bool isUnsaved, {String? contactName}) async {
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

    final unsavedLeads = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM leads WHERE is_unsaved = 1')) ??
        0;

    final totalMessages = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM messages')) ??
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
      'recentActivity': recentActivity,
    };
  }

  // --- Data Management ---

  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('leads');
    await db.delete('contacts_cache');
  }
}
