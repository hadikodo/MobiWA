// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lead.dart';

class DatabaseService {
  static Database? _db;
  static const String _dbName = 'mobiwha.db';
  static const int _version = 1;

  static Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE leads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            is_unsaved INTEGER DEFAULT 0,
            is_group INTEGER DEFAULT 0,
            source TEXT DEFAULT 'notification',
            package_name TEXT DEFAULT 'com.whatsapp'
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_sender ON leads(sender)
        ''');
        await db.execute('''
          CREATE INDEX idx_timestamp ON leads(timestamp DESC)
        ''');
        await db.execute('''
          CREATE TABLE contacts_cache (
            normalized_phone TEXT PRIMARY KEY,
            display_name TEXT,
            synced_at INTEGER
          )
        ''');
      },
    );
  }

  /// Insert a lead. Returns true if inserted (false if duplicate).
  static Future<bool> insertLead(Lead lead) async {
    final db = await database;
    // Deduplication: same sender + message within 60 seconds window
    final existing = await db.query(
      'leads',
      where: 'sender = ? AND message = ? AND ABS(timestamp - ?) < 60000',
      whereArgs: [lead.sender, lead.message, lead.timestamp],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    await db.insert('leads', lead.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  /// Insert multiple leads (from backup). Returns count of new inserts.
  static Future<int> insertLeadsBatch(List<Lead> leads) async {
    final db = await database;
    int count = 0;
    final batch = db.batch();
    for (final lead in leads) {
      batch.insert('leads', lead.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      count++;
    }
    await batch.commit(noResult: true);
    return count;
  }

  /// Get all leads, newest first
  static Future<List<Lead>> getAllLeads({int limit = 500}) async {
    final db = await database;
    final maps = await db.query('leads',
        orderBy: 'timestamp DESC', limit: limit);
    return maps.map(Lead.fromMap).toList();
  }

  /// Get only unsaved number leads
  static Future<List<Lead>> getUnsavedLeads({int limit = 500}) async {
    final db = await database;
    final maps = await db.query('leads',
        where: 'is_unsaved = 1',
        orderBy: 'timestamp DESC',
        limit: limit);
    return maps.map(Lead.fromMap).toList();
  }

  /// Get all messages from a specific sender
  static Future<List<Lead>> getLeadsBySender(String sender) async {
    final db = await database;
    final maps = await db.query('leads',
        where: 'sender = ?',
        whereArgs: [sender],
        orderBy: 'timestamp ASC');
    return maps.map(Lead.fromMap).toList();
  }

  /// Search messages by keyword
  static Future<List<Lead>> searchLeads(String query) async {
    final db = await database;
    final maps = await db.query('leads',
        where: 'message LIKE ? OR sender LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'timestamp DESC',
        limit: 200);
    return maps.map(Lead.fromMap).toList();
  }

  /// Get unique senders with unsaved numbers and their stats
  static Future<List<Map<String, dynamic>>> getUnsavedSenders() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        sender,
        COUNT(*) as message_count,
        MAX(timestamp) as last_seen,
        MIN(timestamp) as first_seen,
        message as last_message
      FROM leads
      WHERE is_unsaved = 1
      GROUP BY sender
      ORDER BY last_seen DESC
    ''');
  }

  /// Summary stats
  static Future<Map<String, int>> getStats() async {
    final db = await database;
    final total = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM leads')) ?? 0;
    final unsaved = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM leads WHERE is_unsaved = 1')) ?? 0;
    final today = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM leads WHERE timestamp > ?',
        [DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch])) ?? 0;
    final uniqueUnsaved = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(DISTINCT sender) FROM leads WHERE is_unsaved = 1')) ?? 0;
    return {
      'total': total,
      'unsaved': unsaved,
      'today': today,
      'uniqueUnsaved': uniqueUnsaved,
    };
  }

  /// Update is_unsaved flag for a sender
  static Future<void> markSenderUnsaved(String sender, bool isUnsaved) async {
    final db = await database;
    await db.update('leads', {'is_unsaved': isUnsaved ? 1 : 0},
        where: 'sender = ?', whereArgs: [sender]);
  }

  // --- Contacts Cache ---

  static Future<void> syncContacts(Map<String, String> normalizedPhoneToName) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in normalizedPhoneToName.entries) {
      batch.insert(
        'contacts_cache',
        {'normalized_phone': entry.key, 'display_name': entry.value, 'synced_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<bool> isPhoneInContacts(String normalizedPhone) async {
    final db = await database;
    final result = await db.query('contacts_cache',
        where: 'normalized_phone = ?',
        whereArgs: [normalizedPhone],
        limit: 1);
    return result.isNotEmpty;
  }

  static Future<void> clearLeads() async {
    final db = await database;
    await db.delete('leads');
  }
}
