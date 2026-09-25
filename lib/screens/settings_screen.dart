// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/contact_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _contactsGranted = false;
  bool _isSyncing = false;
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await ContactService.hasPermission();
    if (mounted) setState(() => _contactsGranted = granted);
  }

  void _showStatus(String msg) {
    setState(() => _statusMsg = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _statusMsg = '');
    });
  }

  Future<void> _handleSyncContacts() async {
    setState(() => _isSyncing = true);
    final count = await ContactService.syncContacts();
    setState(() => _isSyncing = false);

    if (count >= 0) {
      _showStatus('✓ Synced $count contacts from phonebook.');
      _checkPermissions();
    } else {
      _showStatus('✗ Contact permission not granted.');
    }
  }

  void _showImportDialog() {
    final csvController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Leads from CSV'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste CSV content with headers (Phone, Name, Status, Notes):',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: csvController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText:
                    "Phone,Name,Status,Notes\n+1234567890,Acme Supplies,New,Inquiry about goods\n+9876543210,Jane Smith,Qualified,Met at expo",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final content = csvController.text.trim();
              if (content.isEmpty) return;

              final count = await ExportService.importLeadsFromCSV(content);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                _showStatus('✓ Successfully imported $count leads.');
              }
            },
            child: const Text('Import Records'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Storage')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_statusMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card(
                color: _statusMsg.startsWith('✓')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _statusMsg,
                    style: TextStyle(
                      color: _statusMsg.startsWith('✓')
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // Privacy Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              color: const Color(0xFF0D9488).withAlpha(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: Color(0xFF0D9488), size: 36),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '100% Local & Private',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All leads, messages, and contacts are stored in your device\'s local SQLite database. No data is sent to external servers.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Device Permissions Section
          const _SettingsSectionHeader(title: 'Device Permissions'),
          ListTile(
            leading: Icon(
              Icons.contacts_rounded,
              color: _contactsGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Contacts Access'),
            subtitle: Text(
              _contactsGranted
                  ? 'Granted — Used to cross-reference unsaved phone numbers'
                  : 'Not Granted — Tap to request permission',
            ),
            trailing: _contactsGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : TextButton(
                    onPressed: () async {
                      await ContactService.requestPermission();
                      _checkPermissions();
                    },
                    child: const Text('Grant'),
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Sync Phone Contacts'),
            subtitle: Text(
              ContactService.lastSyncTime != null
                  ? 'Last synced: ${fmt.format(ContactService.lastSyncTime!)} (${ContactService.cachedCount} numbers cached)'
                  : 'Never synced',
            ),
            trailing: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isSyncing ? null : _handleSyncContacts,
          ),

          const Divider(),

          // Export & Import Section
          const _SettingsSectionHeader(title: 'Export & Import'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export All Leads (CSV)'),
            subtitle: const Text('Generates spreadsheet of all recorded leads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final count = await ExportService.exportLeadsToCSV();
              _showStatus('✓ Exported $count leads.');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('Export Unsaved Leads (CSV)'),
            subtitle: const Text('Only leads without matching phonebook entries'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final count =
                  await ExportService.exportLeadsToCSV(onlyUnsaved: true);
              _showStatus('✓ Exported $count unsaved leads.');
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import Leads from CSV'),
            subtitle: const Text('Paste or import CSV rows into local database'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showImportDialog,
          ),

          const Divider(),

          // Danger Zone / Database Management
          const _SettingsSectionHeader(title: 'Database Management'),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
            title: const Text('Clear All Local Data',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text(
                'Permanently removes all local leads, messages, and cache'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear All Local Data?'),
                  content: const Text(
                    'This will permanently delete all leads and message records from this device. Make sure you export a CSV backup first.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete All',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await DatabaseService.clearAllData();
                _showStatus('✓ Local database cleared.');
              }
            },
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'MobiWA v1.0.0 • Local Lead Management',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  const _SettingsSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
