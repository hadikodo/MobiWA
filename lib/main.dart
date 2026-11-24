import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/auth.dart';
import 'data/device.dart';
import 'data/models.dart';
import 'data/secure_session_storage.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_status.dart';
import 'services/jobs.dart';
import 'services/native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Log every error that nothing else handled, so it shows up in logcat
  // ("MobiWA error") instead of disappearing.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('MobiWA error (UI): ${details.exceptionAsString()}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('MobiWA error (async): $error\n$stack');
    return true; // handled: keep the app running
  };
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseKey,
    // Android: session in Keystore-encrypted storage. Web: browser storage.
    authOptions: const FlutterAuthClientOptions(
      localStorage: kIsWeb ? null : SecureSessionStorage(),
    ),
  );
  Native.init();
  await Device.load(); // this phone's id + saved session token (sent with every request)
  runApp(const MobiWAApp());
}

class MobiWAApp extends StatelessWidget {
  const MobiWAApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MobiWA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const AuthGate(),
        // Wide screens: keep content at a readable width, centred.
        builder: (context, child) => LayoutBuilder(
          builder: (context, box) => box.maxWidth <= 1200
              ? child!
              : ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Material(elevation: 1, child: child),
                    ),
                  ),
                ),
        ),
      );
}

/// Shows the login screen or the app, following the Supabase session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (s) {
        if (s.event == AuthChangeEvent.signedOut) {
          for (final j in Job.all) {
            j.stop();
          }
          // Not started by the app (e.g. the admin ended the session and the
          // refresh token stopped working): tell the user why.
          if (!Auth.signingOut && Auth.profile.value != null) {
            Auth.signOutReason.value ??=
                'You were signed out. Your admin ended this session — sign in again.';
            Device.setToken(null);
          }
          Auth.profile.value = null;
        }
      },
      // Supabase reports failed background token refreshes (e.g. no network
      // while WhatsApp is in front) as stream errors. It retries by itself;
      // without this handler they were "uncaught" and froze the app under
      // the debugger.
      onError: (Object e) => debugPrint('MobiWA auth stream: $e'),
    );
  }

  /// Re-opens a saved session on app start.
  Future<void> _restore() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      try {
        await Auth.restoreSession();
      } catch (e) {
        debugPrint('MobiWA restore failed: $e');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ValueListenableBuilder<Profile?>(
      valueListenable: Auth.profile,
      builder: (context, profile, _) => profile == null
          ? ValueListenableBuilder<String?>(
              valueListenable: Auth.signOutReason,
              builder: (context, reason, _) => LoginScreen(key: ValueKey(reason), message: reason),
            )
          // A new key per account resets tabs and screens on account switch.
          : Shell(key: ValueKey(profile.id), isAdmin: profile.isAdmin),
    );
  }
}

/// Bottom navigation: Home · Contacts · (Admin) · Settings.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.isAdmin});
  final bool isAdmin;

  static _ShellState? _current;

  static const home = 0;
  static const contacts = 1;

  /// Switches the bottom tab from anywhere (also from pushed screens).
  static void goTo(BuildContext context, int tab) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _current?.select(tab);
  }

  static void goToSettings(BuildContext context) =>
      goTo(context, (_current?.widget.isAdmin ?? false) ? 3 : 2);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _deviceCheck;
  Timer? _webStatusPoll;

  void select(int tab) => setState(() => _tab = tab);

  @override
  void initState() {
    super.initState();
    Shell._current = this;
    WidgetsBinding.instance.addObserver(this);
    AppStatus.instance.refresh();
    // Picks up an admin "force logout" within a minute.
    _deviceCheck = Timer.periodic(const Duration(seconds: 60), (_) => Auth.verifyDevice());
    // Web: notice when the extension / WhatsApp Web tab becomes available.
    if (kIsWeb) {
      _webStatusPoll = Timer.periodic(const Duration(seconds: 4), (_) {
        if (Job.active == null) AppStatus.instance.refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back from Android settings (e.g. after enabling Accessibility),
      // and check this phone still holds the account.
      AppStatus.instance.refresh();
      if (Job.active == null) Auth.verifyDevice();
    }
  }

  @override
  void dispose() {
    _deviceCheck?.cancel();
    _webStatusPoll?.cancel();
    if (Shell._current == this) Shell._current = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.isAdmin;
    final pages = [
      const HomeScreen(),
      const ContactsScreen(),
      if (admin) const AdminScreen(),
      const SettingsScreen(),
    ];
    final items = [
      (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
      (icon: Icons.folder_outlined, selected: Icons.folder_rounded, label: 'Contacts'),
      if (admin)
        (
          icon: Icons.admin_panel_settings_outlined,
          selected: Icons.admin_panel_settings_rounded,
          label: 'Admin'
        ),
      (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'Settings'),
    ];
    final body = IndexedStack(index: _tab, children: pages);

    // Wide screens (web / tablets): side rail + content column.
    if (MediaQuery.sizeOf(context).width >= 840) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/images/logo.png', width: 44, height: 44),
                ),
              ),
              destinations: [
                for (final i in items)
                  NavigationRailDestination(
                    icon: Icon(i.icon),
                    selectedIcon: Icon(i.selected),
                    label: Text(i.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: select,
        destinations: [
          for (final i in items)
            NavigationDestination(
              icon: Icon(i.icon),
              selectedIcon: Icon(i.selected),
              label: i.label,
            ),
        ],
      ),
    );
  }
}
