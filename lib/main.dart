// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/notification_service.dart';
import 'services/contact_service.dart';
import 'services/backup_parser.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize DB
  await DatabaseService.database;

  // Start listening to notification EventChannel
  NotificationService.startListening();

  runApp(const MobiWHAApp());
}

class MobiWHAApp extends StatefulWidget {
  const MobiWHAApp({super.key});

  @override
  State<MobiWHAApp> createState() => _MobiWHAAppState();
}

class _MobiWHAAppState extends State<MobiWHAApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Run background initializations after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _runInit());
  }

  Future<void> _runInit() async {
    // 1. Sync device contacts (runs silently, no dialog if permission already granted)
    await ContactService.requestAndSync();

    // 2. Auto-run backup scan on first launch
    final stats = await DatabaseService.getStats();
    if (stats['total'] == 0) {
      // First launch: try to import historical messages from backup
      await BackupParser.parseAll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permission when user returns from settings
      NotificationService.startListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobiWHA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A884), // WhatsApp green
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A884),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const _PermissionGate(),
    );
  }
}

/// Handles the one-time notification permission prompt on first launch
class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  bool? _hasPermission;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final granted = await NotificationService.hasPermission();
    if (mounted) setState(() => _hasPermission = granted);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPermission == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasPermission == true) {
      return const HomeScreen();
    }
    // Show permission request screen
    return _PermissionRequestScreen(onGranted: () {
      setState(() => _hasPermission = true);
    });
  }
}

class _PermissionRequestScreen extends StatelessWidget {
  final VoidCallback onGranted;
  const _PermissionRequestScreen({required this.onGranted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_rounded, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 32),
              Text('MobiWHA',
                  style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('WhatsApp Message & Lead Collector',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 48),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _PermItem(
                        icon: Icons.notifications,
                        title: 'Notification Access',
                        desc: 'Required to capture incoming WhatsApp messages in real-time',
                      ),
                      const Divider(),
                      _PermItem(
                        icon: Icons.folder_open,
                        title: 'Storage Access',
                        desc: 'Required to read historical messages from WhatsApp backup',
                      ),
                      const Divider(),
                      _PermItem(
                        icon: Icons.contacts,
                        title: 'Contacts Access',
                        desc: 'Required to identify unsaved phone numbers',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.security),
                  label: const Text('Grant Notification Access', style: TextStyle(fontSize: 16)),
                  onPressed: () async {
                    await NotificationService.openSettings();
                    // Check again after user returns
                    await Future.delayed(const Duration(seconds: 2));
                    final granted = await NotificationService.hasPermission();
                    if (granted) onGranted();
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onGranted, // Skip for now, go to home
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _PermItem({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(desc, style: TextStyle(fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
