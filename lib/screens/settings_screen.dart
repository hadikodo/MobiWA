// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/contact_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _listenerEnabled = false;
  bool _batteryOptimized = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final listener = await NotificationService.hasPermission();
    final battery = await NotificationService.isBatteryOptimized();
    if (mounted) setState(() {
      _listenerEnabled = listener;
      _batteryOptimized = battery;
    });
  }

  void _showStatus(String msg) {
    setState(() => _status = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _status = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Permissions Section
          const _SectionHeader(title: 'Permissions'),
          ListTile(
            leading: Icon(Icons.notifications_active,
                color: _listenerEnabled ? Colors.green : Colors.red),
            title: const Text('Notification Access'),
            subtitle: Text(_listenerEnabled ? 'Granted ✓' : 'Not granted — tap to enable'),
            trailing: _listenerEnabled
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.warning, color: Colors.orange),
            onTap: () async {
              await NotificationService.openSettings();
              await Future.delayed(const Duration(seconds: 2));
              await _checkStatus();
            },
          ),
          ListTile(
            leading: Icon(Icons.battery_saver,
                color: _batteryOptimized ? Colors.orange : Colors.green),
            title: const Text('Battery Optimization'),
            subtitle: Text(_batteryOptimized
                ? 'App may be killed — tap to disable'
                : 'Exempt ✓ (recommended)'),
            trailing: _batteryOptimized
                ? const Icon(Icons.warning, color: Colors.orange)
                : const Icon(Icons.check_circle, color: Colors.green),
            onTap: () async {
              await NotificationService.requestBatteryExemption();
              await Future.delayed(const Duration(seconds: 2));
              await _checkStatus();
            },
          ),

          const Divider(),

          // Contacts Section
          const _SectionHeader(title: 'Contacts'),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Device Contacts'),
            subtitle: Text(ContactService.isSynced
                ? 'Last synced: ${ContactService.cachedCount} contacts cached'
                : 'Not synced yet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              _showStatus('Syncing contacts...');
              await ContactService.requestAndSync();
              _showStatus('✓ Synced ${ContactService.cachedCount} contacts');
            },
          ),

          const Divider(),

          // Export Section
          const _SectionHeader(title: 'Export'),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export Unsaved Contacts (CSV)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: ExportService.exportUnsavedToCSV,
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline),
            title: const Text('Export All Messages (CSV)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: ExportService.exportAllToCSV,
          ),

          const Divider(),

          // Danger Zone
          const _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Permanently delete all captured messages'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear All Data?'),
                  content: const Text('This will permanently delete all captured messages. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseService.clearLeads();
                _showStatus('✓ All data cleared');
              }
            },
          ),

          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: _status.startsWith('✓') ? Colors.green.shade50 : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_status,
                      style: TextStyle(
                          color: _status.startsWith('✓') ? Colors.green.shade700 : Colors.orange.shade700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}
