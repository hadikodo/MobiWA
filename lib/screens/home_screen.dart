import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/backup_parser.dart';

import 'unsaved_screen.dart';
import 'messages_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {'total': 0, 'unsaved': 0, 'today': 0, 'uniqueUnsaved': 0};
  bool _listenerActive = false;
  bool _syncing = false;
  String _syncStatus = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _init();
    // Refresh stats when new leads arrive
    NotificationService.newLeads.listen((_) => _loadStats());
  }

  Future<void> _init() async {
    await _checkListener();
    await _loadStats();
  }

  Future<void> _checkListener() async {
    final active = await NotificationService.hasPermission();
    if (mounted) setState(() => _listenerActive = active);
  }

  Future<void> _loadStats() async {
    final stats = await DatabaseService.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _runBackupScan() async {
    setState(() { _syncing = true; _syncStatus = 'Scanning WhatsApp backup...'; });
    final result = await BackupParser.parseAll();
    setState(() {
      _syncing = false;
      _syncStatus = result.success
          ? '✓ Imported ${result.imported} historical messages'
          : '✗ ${result.error}';
    });
    await _loadStats();
    if (mounted) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _syncStatus = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _DashboardBody(
            stats: _stats,
            listenerActive: _listenerActive,
            syncing: _syncing,
            syncStatus: _syncStatus,
            onScanBackup: _runBackupScan,
            onRefreshStats: _loadStats,
          ),
          const UnsavedScreen(),
          const MessagesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.person_off_outlined), selectedIcon: Icon(Icons.person_off), label: 'Unsaved'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'Messages'),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final Map<String, int> stats;
  final bool listenerActive;
  final bool syncing;
  final String syncStatus;
  final VoidCallback? onScanBackup;
  final VoidCallback? onRefreshStats;

  const _DashboardBody({
    this.stats = const {},
    this.listenerActive = false,
    this.syncing = false,
    this.syncStatus = '',
    this.onScanBackup,
    this.onRefreshStats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('MobiWHA'),
          backgroundColor: theme.colorScheme.surface,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: onRefreshStats,
              tooltip: 'Refresh stats',
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Listener status banner
              _StatusBanner(active: listenerActive, context: context),
              const SizedBox(height: 20),

              // Stats grid
              Text('Overview', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _StatCard(
                    label: 'Total Messages',
                    value: '${stats['total'] ?? 0}',
                    icon: Icons.message_outlined,
                    color: Colors.blue,
                  ),
                  _StatCard(
                    label: 'Unsaved Numbers',
                    value: '${stats['uniqueUnsaved'] ?? 0}',
                    icon: Icons.person_off_outlined,
                    color: Colors.orange,
                  ),
                  _StatCard(
                    label: 'Messages Today',
                    value: '${stats['today'] ?? 0}',
                    icon: Icons.today_outlined,
                    color: Colors.green,
                  ),
                  _StatCard(
                    label: 'Unsaved Messages',
                    value: '${stats['unsaved'] ?? 0}',
                    icon: Icons.mark_chat_unread_outlined,
                    color: Colors.purple,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Backup scan section
              Text('Historical Data', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('WhatsApp Backup Scan',
                              style: theme.textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reads your local WhatsApp backup file to import all historical messages from unsaved contacts.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (syncStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(syncStatus,
                              style: TextStyle(
                                  color: syncStatus.startsWith('✓') ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w500)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: syncing ? null : onScanBackup,
                          icon: syncing
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.search),
                          label: Text(syncing ? 'Scanning...' : 'Scan Backup Now'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ]),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool active;
  final BuildContext context;
  const _StatusBanner({required this.active, required this.context});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: active
          ? Colors.green.withAlpha(30)
          : Colors.red.withAlpha(30),
      child: ListTile(
        leading: Icon(
          active ? Icons.sensors : Icons.sensors_off,
          color: active ? Colors.green : Colors.red,
        ),
        title: Text(
          active ? 'Listener Active' : 'Listener Inactive',
          style: TextStyle(
            color: active ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          active
              ? 'Capturing WhatsApp messages in real-time'
              : 'Tap to enable notification access',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: active
            ? null
            : TextButton(
                onPressed: () async {
                  await NotificationService.openSettings();
                },
                child: const Text('Enable'),
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
