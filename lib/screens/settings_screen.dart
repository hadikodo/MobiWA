// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../services/contact_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/whatsapp_service.dart';
import '../services/whatsapp_export_parser.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _contactsGranted = false;
  bool _notificationAccessGranted = false;
  bool _accessibilityGranted = false;
  bool _isSyncing = false;
  bool _isImportingContacts = false;
  String _statusMsg = '';
  int _cachedContactCount = 0;
  DateTime? _lastContactsSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WhatsAppService.pendingSharedChatExport
        .addListener(_handleSharedChatExport);
    DatabaseService.dataRevision.addListener(_refreshContactSyncInfo);
    _checkPermissions();
    _refreshContactSyncInfo();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _handleSharedChatExport());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DatabaseService.dataRevision.removeListener(_refreshContactSyncInfo);
    WhatsAppService.pendingSharedChatExport
        .removeListener(_handleSharedChatExport);
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
    final notificationGranted =
        await _captureChannel.invokeMethod<bool>('hasNotificationAccess') ??
            false;
    final accessibilityGranted = await WhatsAppService.hasAccessibilityAccess();
    if (mounted) {
      setState(() {
        _contactsGranted = granted;
        _notificationAccessGranted = notificationGranted;
        _accessibilityGranted = accessibilityGranted;
      });
    }
  }

  static const _captureChannel =
      MethodChannel('com.mobiwha.mobiwha/notification_capture');

  void _showStatus(String msg) {
    setState(() => _statusMsg = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _statusMsg = '');
    });
  }

  Future<void> _handleSyncContacts() async {
    setState(() => _isSyncing = true);
    final count = await ContactService.syncContacts();
    await DatabaseService.processPendingNotifications();
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
          'Added $imported new phone contacts to your local Leads list.');
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

  Future<void> _importWhatsAppChatExport() async {
    try {
      final export = await WhatsAppService.pickChatExport();
      if (!mounted) return;
      if (export == null) return;
      await _importWhatsAppChatContent(export);
    } on PlatformException catch (error) {
      if (mounted) {
        _showStatus(error.message ?? 'Could not read that chat export.');
      }
    } catch (error) {
      if (mounted) _showStatus('Could not import chat export: $error');
    }
  }

  void _handleSharedChatExport() {
    final export = WhatsAppService.pendingSharedChatExport.value;
    if (export == null || !mounted) return;
    WhatsAppService.pendingSharedChatExport.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _importWhatsAppChatContent(export);
    });
  }

  int? _suggestLeadForChatExport(String? fileName, List<Lead> leads) {
    if (fileName == null || fileName.trim().isEmpty) return null;

    var stem = fileName.trim().replaceFirst(RegExp(r'\.[^.]+$'), '');
    const prefixes = [
      'whatsapp chat with ',
      'whatsapp chat - ',
      'chat with ',
      'whatsapp chat ',
      'whatsapp - ',
      'chat - ',
    ];
    final lowerStem = stem.toLowerCase();
    for (final prefix in prefixes) {
      if (lowerStem.startsWith(prefix)) {
        stem = stem.substring(prefix.length).trim();
        break;
      }
    }

    String normalizeName(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final normalizedStem = normalizeName(stem);
    final matchingIds = <int>{};
    for (final lead in leads) {
      final id = lead.id;
      if (id == null) continue;

      if (normalizedStem.isNotEmpty &&
          normalizeName(lead.displayName) == normalizedStem) {
        matchingIds.add(id);
      }

      final filePhoneTokens = RegExp(r'\+?\d[\d\s().-]{5,}\d')
          .allMatches(fileName)
          .map((match) => match.group(0)!.replaceAll(RegExp(r'\D'), ''))
          .where((digits) => digits.length >= 7 && digits.length <= 15);
      final leadDigits = lead.phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (leadDigits.length >= 7 && filePhoneTokens.contains(leadDigits)) {
        matchingIds.add(id);
      }
    }
    return matchingIds.length == 1 ? matchingIds.single : null;
  }

  Future<void> _importWhatsAppChatContent(Map<String, String> export) async {
    try {
      final content = export['content'] ?? '';
      final parsed = WhatsAppExportParser.parse(content);
      if (parsed.isEmpty) {
        _showStatus('No readable chat messages were found in that text file.');
        return;
      }
      final leads = await DatabaseService.getLeads(limit: 50000);
      if (!mounted) return;
      if (leads.isEmpty) {
        _showStatus('Load contacts or add a lead before importing a chat.');
        return;
      }

      int? selectedLeadId = _suggestLeadForChatExport(export['name'], leads);
      final datePattern = DateFormat.yMd().pattern ?? 'd/M/y';
      var dayFirstDates = datePattern.indexOf('d') < datePattern.indexOf('M');
      final selfNameController = TextEditingController(text: 'You');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Import WhatsApp chat export'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(export['name'] ?? 'Chat export'),
                    const SizedBox(height: 4),
                    Builder(builder: (context) {
                      final preview = WhatsAppExportParser.parse(
                        content,
                        selfName: selfNameController.text.trim().isEmpty
                            ? 'You'
                            : selfNameController.text.trim(),
                        dayFirstForAmbiguousDates: dayFirstDates,
                      );
                      final incoming = preview
                          .where((message) => message.direction == 'incoming')
                          .length;
                      final outgoing = preview.length - incoming;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${preview.length} messages found • $incoming incoming • $outgoing outgoing',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (preview.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'No messages match the selected date and sender format.',
                              ),
                            )
                          else ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Preview',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            ...preview.take(3).map((message) => Card(
                                  margin: const EdgeInsets.only(top: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${message.sender} • ${message.direction} • ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.fromMillisecondsSinceEpoch(message.timestamp))}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          message.text,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedLeadId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Save this conversation under',
                      ),
                      items: leads
                          .where((lead) => lead.id != null)
                          .map((lead) => DropdownMenuItem<int>(
                                value: lead.id,
                                child: Text(
                                    '${lead.displayName} • ${lead.phoneNumber}',
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedLeadId = value),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<bool>(
                      initialValue: dayFirstDates,
                      decoration: const InputDecoration(
                        labelText: 'Order for ambiguous dates',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('Day / Month / Year'),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text('Month / Day / Year'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => dayFirstDates = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: selfNameController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Your sender name in this export',
                        helperText:
                            'Usually “You”; used to mark your messages outgoing.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose the matching lead. For group exports, messages from all other participants are stored under that lead. Media files are not included in text exports.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedLeadId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Import messages'),
              ),
            ],
          ),
        ),
      );
      final selfName = selfNameController.text.trim().isEmpty
          ? 'You'
          : selfNameController.text.trim();
      selfNameController.dispose();
      if (confirmed != true || selectedLeadId == null || !mounted) return;

      final classified = WhatsAppExportParser.parse(
        content,
        selfName: selfName,
        dayFirstForAmbiguousDates: dayFirstDates,
      )
          .map((message) => (
                sender: message.sender,
                text: message.text,
                direction: message.direction,
                timestamp: message.timestamp,
              ))
          .toList();
      final imported = await DatabaseService.importWhatsAppExportMessages(
        selectedLeadId!,
        classified,
      );
      if (mounted) {
        _showStatus(
            'Imported $imported new messages; duplicates were skipped.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showStatus(error.message ?? 'Could not read that chat export.');
      }
    } catch (error) {
      if (mounted) _showStatus('Could not import chat export: $error');
    }
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
                            'Matched contacts and WhatsApp notification previews are stored in your device\'s local database. No data is sent to external servers.',
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
            title: const Text('Load Contacts into Leads'),
            subtitle: const Text(
              'Copies names and phone numbers into the local lead list; existing numbers are skipped',
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

          ListTile(
            leading: Icon(
              Icons.notifications_active_outlined,
              color: _notificationAccessGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('WhatsApp Message Capture'),
            subtitle: Text(
              _notificationAccessGranted
                  ? 'Enabled — incoming WhatsApp previews are saved locally'
                  : 'Android requires you to enable notification access once',
            ),
            trailing: _notificationAccessGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: () async {
              await _captureChannel
                  .invokeMethod<void>('openNotificationAccessSettings');
              await _checkPermissions();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.touch_app_outlined,
              color: _accessibilityGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('WhatsApp Auto-Send'),
            subtitle: Text(
              _accessibilityGranted
                  ? 'Enabled — bulk messages will send automatically'
                  : 'Requires accessibility service to press send',
            ),
            trailing: _accessibilityGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: () async {
              await WhatsAppService.openAccessibilitySettings();
              await _checkPermissions();
            },
          ),

          const Divider(),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'MobiWA captures incoming message previews from WhatsApp and WhatsApp Business after notification access is enabled. Android controls this permission. Group summaries without a clear sender are skipped.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
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
                const Text('Paste or import CSV rows into local database'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showImportDialog,
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: const Text('Import WhatsApp Chat Export'),
            subtitle: const Text(
              'Import a plain-text .txt export into a selected lead; repeated imports skip duplicates',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _importWhatsAppChatExport,
          ),

          const Divider(),

          // Danger Zone / Database Management
          const _SettingsSectionHeader(title: 'Database Management'),
          ListTile(
            leading:
                const Icon(Icons.delete_forever_rounded, color: Colors.red),
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
                    'This permanently deletes local leads, messages, and the synced contacts cache. Automatic contact imports stay paused afterward; use “Load Contacts into Leads” if you want to restore them.',
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
