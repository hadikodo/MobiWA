// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/contact_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/whatsapp_service.dart';
import 'auto_responder_screen.dart';
import 'broadcast_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _contactsGranted = false;
  bool _accessibilityGranted = false;
  bool _notificationGranted = false;
  bool _isSyncing = false;
  bool _isImportingContacts = false;
  String _statusMsg = '';
  int _cachedContactCount = 0;
  DateTime? _lastContactsSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DatabaseService.dataRevision.addListener(_refreshContactSyncInfo);
    _checkPermissions();
    _refreshContactSyncInfo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DatabaseService.dataRevision.removeListener(_refreshContactSyncInfo);
    super.dispose();
  }

  Future<void> _refreshContactSyncInfo() async {
    final info = await DatabaseService.getContactsSyncInfo();
    if (!mounted) return;
    final timestamp = info['lastSyncAt'];
    setState(() {
      _cachedContactCount = info['count'] ?? 0;
      _lastContactsSyncAt = timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp);
    });
  }

  Future<void> _checkPermissions() async {
    final granted = await ContactService.hasPermission();
    final accessibilityGranted = await WhatsAppService.hasAccessibilityAccess();
    final notificationGranted = await WhatsAppService.hasNotificationAccess();
    if (mounted) {
      setState(() {
        _contactsGranted = granted;
        _accessibilityGranted = accessibilityGranted;
        _notificationGranted = notificationGranted;
      });
    }
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

  Future<void> _handleImportContactsAsLeads() async {
    setState(() => _isImportingContacts = true);
    final synced = await ContactService.syncContacts();
    final imported =
        synced < 0 ? -1 : await ContactService.importDeviceContactsAsLeads();
    if (!mounted) return;
    setState(() => _isImportingContacts = false);
    if (imported >= 0) {
      await DatabaseService.setAutoImportContactsEnabled(true);
      _showStatus(
          'Added $imported new phone contacts to your local CRM Leads list.');
    } else {
      _showStatus('Allow Contacts access to load phone contacts.');
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
      appBar: AppBar(title: const Text('Settings & Preferences')),
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
                            '100% Local & Private CRM',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All customer contacts and WhatsApp conversations remain securely stored inside your local SQLite database.',
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

          // Mobi AI & Automation
          const _SettingsSectionHeader(title: 'Mobi AI & Broadcast Campaigns'),
          ListTile(
            leading: const Icon(Icons.smart_toy_rounded, color: Color(0xFF10B981)),
            title: const Text('AI Auto-Responder'),
            subtitle: const Text(
              'Auto-reply to WhatsApp notifications using Gemini trained on your tone and business guidelines',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AutoResponderScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.campaign_rounded, color: Color(0xFF0D9488)),
            title: const Text('Broadcast Campaigns by List'),
            subtitle: const Text(
              'Send messages, images, videos, audio to targeted AI customer lists',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BroadcastScreen()),
              );
            },
          ),
          const Divider(),

          // Device Permissions & WhatsApp Automation
          const _SettingsSectionHeader(title: 'WhatsApp Automation & Permissions'),
          ListTile(
            leading: Icon(
              Icons.touch_app_outlined,
              color: _accessibilityGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('WhatsApp Chat Reader (Accessibility)'),
            subtitle: Text(
              _accessibilityGranted
                  ? 'Enabled — Mobi AI reads conversations directly from WhatsApp'
                  : 'Required to read chat history for automated profiling',
            ),
            trailing: _accessibilityGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : TextButton(
                    onPressed: () async {
                      await WhatsAppService.openAccessibilitySettings();
                      await _checkPermissions();
                    },
                    child: const Text('Enable'),
                  ),
            onTap: () async {
              await WhatsAppService.openAccessibilitySettings();
              await _checkPermissions();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.notifications_active_outlined,
              color: _notificationGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Background Auto-Responder (Notification Access)'),
            subtitle: Text(
              _notificationGranted
                  ? 'Enabled — Mobi AI detects incoming WhatsApp notifications and replies'
                  : 'Required for auto-responder to receive incoming messages',
            ),
            trailing: _notificationGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : TextButton(
                    onPressed: () async {
                      await WhatsAppService.openNotificationAccessSettings();
                      await _checkPermissions();
                    },
                    child: const Text('Enable'),
                  ),
            onTap: () async {
              await WhatsAppService.openNotificationAccessSettings();
              await _checkPermissions();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.contacts_rounded,
              color: _contactsGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Phone Contacts Access'),
            subtitle: Text(
              _contactsGranted
                  ? 'Granted — Used to identify unsaved numbers'
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
              _lastContactsSyncAt != null
                  ? 'Last synced: ${fmt.format(_lastContactsSyncAt!)} ($_cachedContactCount numbers cached)'
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
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded),
            title: const Text('Import Contacts into CRM'),
            subtitle: const Text(
              'Copies names and numbers into your CRM lead directory',
            ),
            trailing: _isImportingContacts
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isImportingContacts ? null : _handleImportContactsAsLeads,
          ),

          const Divider(),

          // Export & Import Section
          const _SettingsSectionHeader(title: 'Data Export & Import'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export All Leads (CSV)'),
            subtitle: const Text('Generates spreadsheet of all customer leads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final count = await ExportService.exportLeadsToCSV();
              _showStatus('✓ Exported $count leads.');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('Export Unsaved Leads (CSV)'),
            subtitle:
                const Text('Only leads without matching phonebook entries'),
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
            subtitle:
                const Text('Paste or import CSV rows into local CRM'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showImportDialog,
          ),

          const Divider(),

          // Database Management
          const _SettingsSectionHeader(title: 'Database Management'),
          ListTile(
            leading:
                const Icon(Icons.delete_forever_rounded, color: Colors.red),
            title: const Text('Clear All Local CRM Data',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text(
                'Permanently removes all local leads, messages, and cache'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear All Local CRM Data?'),
                  content: const Text(
                    'This permanently deletes all local leads, messages, and cached contacts from this device. This action cannot be undone.',
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
                ContactService.clearInMemoryCache();
                _showStatus('✓ Local database cleared.');
              }
            },
          ),

          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const Icon(
                        Icons.auto_awesome,
                        size: 28,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mobi AI CRM',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Autonomous WhatsApp CRM • Version 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Powered by Google Gemini 2.5',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
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
