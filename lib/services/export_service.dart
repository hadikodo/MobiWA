// lib/services/export_service.dart
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';

class ExportService {
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Export leads to CSV with optional filtering
  static Future<int> exportLeadsToCSV({bool onlyUnsaved = false}) async {
    final leads = await DatabaseService.getLeads(
      onlyUnsaved: onlyUnsaved ? true : null,
      limit: 50000,
    );

    if (leads.isEmpty) return 0;

    final rows = <List<dynamic>>[
      [
        'Lead ID',
        'Phone Number',
        'Name',
        'Status',
        'Is Unsaved',
        'Notes',
        'Tags',
        'Created At',
        'Updated At',
        'Message Count',
        'Last Message',
      ],
    ];

    for (final lead in leads) {
      rows.add([
        lead.id ?? '',
        lead.phoneNumber,
        lead.name,
        lead.status,
        lead.isUnsaved ? 'Yes' : 'No',
        lead.notes,
        lead.tags,
        _fmt.format(lead.createdDateTime),
        _fmt.format(lead.updatedDateTime),
        lead.messageCount,
        lead.lastMessage ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final filename = onlyUnsaved
        ? 'mobiwa_unsaved_leads_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv'
        : 'mobiwa_leads_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csvData);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MobiWA Lead Export (${leads.length} records)',
    );

    return leads.length;
  }

  /// Export a single lead and all its message history
  static Future<bool> exportLeadConversation(int leadId) async {
    final lead = await DatabaseService.getLeadById(leadId);
    if (lead == null) return false;

    final messages = await DatabaseService.getMessagesForLead(leadId);

    final rows = <List<dynamic>>[
      ['Lead Name', lead.name],
      ['Phone Number', lead.phoneNumber],
      ['Status', lead.status],
      ['Notes', lead.notes],
      [''],
      ['Message ID', 'Direction', 'Date & Time', 'Message', 'Note'],
    ];

    for (final msg in messages) {
      rows.add([
        msg.id ?? '',
        msg.direction.toUpperCase(),
        _fmt.format(msg.dateTime),
        msg.message,
        msg.note,
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final safePhone = lead.phoneNumber.replaceAll(RegExp(r'[^\w]'), '_');
    final filename = 'mobiwa_transcript_$safePhone.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csvData);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MobiWA Transcript - ${lead.displayName}',
    );

    return true;
  }

  /// Import leads from a CSV string
  static Future<int> importLeadsFromCSV(String csvContent) async {
    try {
      final rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(csvContent.replaceAll('\r\n', '\n'));
      if (rows.length <= 1) return 0;

      int imported = 0;
      // Skip header row
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        // Expect: Phone, Name, Status, Notes
        final phone = row.isNotEmpty ? row[0].toString().trim() : '';
        if (phone.isEmpty) continue;

        final name = row.length > 1 ? row[1].toString().trim() : '';
        final status = row.length > 2 ? row[2].toString().trim() : 'New';
        final notes = row.length > 3 ? row[3].toString().trim() : '';

        await DatabaseService.getOrCreateLead(
          phoneNumber: phone,
          name: name,
          notes: notes,
          status: status.isNotEmpty ? status : 'New',
        );
        imported++;
      }
      return imported;
    } catch (_) {
      return 0;
    }
  }
}
