// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/database_service.dart';
import 'services/contact_service.dart';
import 'services/whatsapp_service.dart';
import 'screens/home_screen.dart';
import 'screens/unsaved_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/settings_screen.dart';

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
  const MobiWAApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D9488); // Modern Teal / Slate tone

    return MaterialApp(
      title: 'MobiWA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryColor,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryColor,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
          color: const Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainNavigationShell(),
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
  Timer? _captureRefreshTimer;
  bool _contactSyncInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncLocalContacts(requestPermission: true);
    _checkForSharedChatExport();
    _captureRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshCapturedMessages(),
    );
  }

  Future<void> _syncLocalContacts({required bool requestPermission}) async {
    if (_contactSyncInProgress) return;
    if (!requestPermission && !await ContactService.hasPermission()) return;

    _contactSyncInProgress = true;
    try {
      final automaticImportEnabled =
          await DatabaseService.isAutomaticContactImportEnabled();
      if (!automaticImportEnabled) {
        await _processPendingNotificationsSafely();
        return;
      }
      // Once Android grants Contacts access, seed the local Leads directory so
      // the app opens with real device contacts instead of an empty dashboard.
      // Both the cache and imported lead records remain local to this device.
      final syncedContacts = await ContactService.syncContacts();
      if (syncedContacts >= 0) {
        await ContactService.importDeviceContactsAsLeads();
      }
      await _processPendingNotificationsSafely();
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
      _refreshCapturedMessages();
      _refreshContactsIfStale();
      _checkForSharedChatExport();
    }
  }

  Future<void> _checkForSharedChatExport() async {
    try {
      final export = await WhatsAppService.takeSharedChatExport();
      if (export == null || !mounted) return;
      setState(() => _currentIndex = 3);
      WhatsAppService.pendingSharedChatExport.value = export;
    } on PlatformException {
      // The share intent is optional; normal app startup should continue.
    }
  }

  Future<void> _refreshCapturedMessages() async {
    await _processPendingNotificationsSafely();
  }

  Future<void> _processPendingNotificationsSafely() async {
    try {
      await DatabaseService.processPendingNotifications();
    } catch (error, stackTrace) {
      debugPrint('MobiWA notification refresh failed: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureRefreshTimer?.cancel();
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
            icon: Icon(Icons.person_off_outlined),
            selectedIcon: Icon(Icons.person_off_rounded),
            label: 'Unsaved',
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
