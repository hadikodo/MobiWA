// lib/services/backup_parser.dart
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/lead.dart';
import '../utils/phone_utils.dart';
import 'database_service.dart';
import 'contact_service.dart';
import 'notification_service.dart';

class BackupParser {
  static const List<String> _fallbackPaths = [
    '/sdcard/WhatsApp/Databases/msgstore.db',
    '/storage/emulated/0/WhatsApp/Databases/msgstore.db',
    '/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db',
    '/sdcard/WhatsApp Business/Databases/msgstore.db',
    '/storage/emulated/0/WhatsApp Business/Databases/msgstore.db',
  ];

  /// Entry point: request storage permission then parse all backup files
  static Future<BackupResult> parseAll() async {
    // Request storage permission
    PermissionStatus status;
    if (Platform.isAndroid) {
      // For Android 11+ use MANAGE_EXTERNAL_STORAGE
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    } else {
      return BackupResult(error: 'Backup parsing only supported on Android');
    }

    if (!status.isGranted) {
      return BackupResult(error: 'Storage permission denied');
    }

    // Get backup paths from native + add fallbacks
    List<String> paths = await NotificationService.getBackupPaths();
    paths.addAll(_fallbackPaths);
    paths = paths.toSet().toList(); // deduplicate

    int totalImported = 0;
    final errors = <String>[];

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;

      try {
        final result = await _parseBackupFile(file);
        totalImported += result;
      } catch (e) {
        errors.add('$path: $e');
      }
    }

    return BackupResult(
      imported: totalImported,
      errors: errors,
    );
  }

  /// Parse a single WhatsApp msgstore.db SQLite file
  static Future<int> _parseBackupFile(File dbFile) async {
    // Copy to app-accessible location first
    final appDir = await getDatabasesPath();
    final tempPath = '$appDir/wa_backup_temp.db';
    await dbFile.copy(tempPath);

    Database? waDb;
    try {
      waDb = await openDatabase(tempPath, readOnly: true);

      // WhatsApp uses different schema versions. Try common table structures.
      final leads = await _extractMessages(waDb);
      if (leads.isEmpty) return 0;

      return await DatabaseService.insertLeadsBatch(leads);
    } finally {
      await waDb?.close();
      // Clean up temp file
      try { await File(tempPath).delete(); } catch (_) {}
    }
  }

  static Future<List<Lead>> _extractMessages(Database waDb) async {
    final leads = <Lead>[];

    // Try modern WhatsApp schema (2021+)
    try {
      final rows = await waDb.rawQuery('''
        SELECT
          m.key_remote_jid AS jid,
          m.data AS message,
          m.timestamp AS ts,
          m.key_from_me AS from_me
        FROM messages m
        WHERE m.key_from_me = 0
          AND m.data IS NOT NULL
          AND m.data != ''
        ORDER BY m.timestamp DESC
        LIMIT 5000
      ''');
      leads.addAll(_rowsToLeads(rows, 'com.whatsapp'));
    } catch (_) {
      // Table structure may differ — try alternative
      try {
        final rows = await waDb.rawQuery('''
          SELECT
            jid,
            text_data AS message,
            received_timestamp AS ts
          FROM message
          WHERE from_me = 0
            AND text_data IS NOT NULL
          ORDER BY received_timestamp DESC
          LIMIT 5000
        ''');
        leads.addAll(_rowsToLeads(rows, 'com.whatsapp'));
      } catch (_) {
        // Could not parse schema
      }
    }

    return leads;
  }

  static List<Lead> _rowsToLeads(List<Map<String, dynamic>> rows, String pkg) {
    final leads = <Lead>[];
    for (final row in rows) {
      final jid = (row['jid'] as String?) ?? '';
      final message = (row['message'] as String?) ?? '';
      final ts = (row['ts'] as int?) ?? 0;

      if (jid.isEmpty || message.isEmpty || ts == 0) continue;

      // Extract phone from JID
      final phone = PhoneUtils.extractFromJid(jid);
      if (phone == null) continue; // Skip groups

      final isUnsaved = ContactService.isUnsaved(phone);

      leads.add(Lead(
        sender: '+$phone',
        message: message,
        timestamp: ts,
        isUnsaved: isUnsaved,
        isGroup: false,
        source: 'backup',
        packageName: pkg,
      ));
    }
    return leads;
  }
}

class BackupResult {
  final int imported;
  final List<String> errors;
  final String? error;

  BackupResult({this.imported = 0, this.errors = const [], this.error});

  bool get success => error == null;
  bool get hasErrors => errors.isNotEmpty;
}
