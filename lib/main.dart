// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/database_service.dart';
import 'services/contact_service.dart';
import 'screens/home_screen.dart';
import 'screens/unsaved_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/permissions_prompt_dialog.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize SQLite database
  await DatabaseService.database;

  runApp(const MobiWAApp());
}

class MobiWAApp extends StatelessWidget {
  final bool skipSplash;

  const MobiWAApp({
    super.key,
    this.skipSplash = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobi AI CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: skipSplash ? const MainNavigationShell() : const SplashScreen(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _contactSyncInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DatabaseService.startNotificationWorker();
    _syncLocalContacts(requestPermission: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionsPromptDialog.checkAndPromptIfNeeded(context);
    });
  }

  Future<void> _syncLocalContacts({required bool requestPermission}) async {
    if (_contactSyncInProgress) return;
    if (!requestPermission && !await ContactService.hasPermission()) return;

    _contactSyncInProgress = true;
    try {
      final automaticImportEnabled =
          await DatabaseService.isAutomaticContactImportEnabled();
      if (!automaticImportEnabled) return;

      final syncedContacts = await ContactService.syncContacts();
      if (syncedContacts >= 0) {
        await ContactService.importDeviceContactsAsLeads();
      }
    } catch (error, stackTrace) {
      debugPrint('MobiWA contact refresh failed: $error\n$stackTrace');
    } finally {
      _contactSyncInProgress = false;
    }
  }

  Future<void> _refreshContactsIfStale() async {
    final lastSync = ContactService.lastSyncTime;
    if (lastSync != null &&
        DateTime.now().difference(lastSync) < const Duration(minutes: 15)) {
      return;
    }
    await _syncLocalContacts(requestPermission: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshContactsIfStale();
      DatabaseService.processPendingNotifications();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          UnsavedScreen(),
          MessagesScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
