// lib/services/export_service.dart
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import 'database_service.dart';

class ExportService {
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Export all unsaved leads to CSV and share
  static Future<void> exportUnsavedToCSV() async {
    final leads = await DatabaseService.getUnsavedLeads(limit: 10000);
    await _exportLeads(leads, 'mobiwha_unsaved_contacts.csv');
  }

  /// Export all leads to CSV and share
  static Future<void> exportAllToCSV() async {
    final leads = await DatabaseService.getAllLeads(limit: 10000);
    await _exportLeads(leads, 'mobiwha_all_messages.csv');
  }

  static Future<void> _exportLeads(List<Lead> leads, String filename) async {
    final rows = <List<dynamic>>[
      ['Phone/Sender', 'Message', 'Date & Time', 'Is Unsaved', 'Source', 'App'],
    ];

    for (final lead in leads) {
      rows.add([
        lead.sender,
        lead.message,
        _fmt.format(lead.dateTime),
        lead.isUnsaved ? 'Yes' : 'No',
        lead.source,
        lead.packageName == 'com.whatsapp.w4b' ? 'WhatsApp Business' : 'WhatsApp',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'MobiWHA Export — ${leads.length} records',
    );
  }
}
