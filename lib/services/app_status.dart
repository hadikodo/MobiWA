import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'native.dart';

/// State of MobiWA's accessibility service.
enum AutomationState {
  /// Bound and working.
  running,

  /// Switched on in Android Settings, but the phone killed it. Android won't
  /// restart it until it is toggled off/on (MobiWA does that itself when it
  /// has the adb-granted permission).
  stopped,

  /// Switched off in Android Settings.
  off,
}

/// What the app needs before the actions can run. Refreshed when the app
/// comes back to the foreground (e.g. after enabling Accessibility).
class AppStatus extends ChangeNotifier {
  AppStatus._();
  static final instance = AppStatus._();

  bool loaded = false;
  AutomationState automation = AutomationState.off;
  List<WaApp> apps = [];
  bool batteryUnrestricted = true;

  /// Web only: "ready", "login" (QR code shown), "closed" or "no_extension".
  String whatsappWeb = 'closed';
  bool isXiaomi = false;

  bool get accessibilityOn => automation == AutomationState.running;
  bool get whatsappInstalled => apps.isNotEmpty;
  bool get ready => accessibilityOn && whatsappInstalled;

  bool _refreshing = false;

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      automation = _parse(await Native.accessibilityState());
      if (automation != AutomationState.running) {
        // Try to bring it back without bothering the user (only works if the
        // user had switched it on before, and with the one-time adb grant).
        if (await Native.tryRestartAccessibility()) {
          automation = _parse(await Native.accessibilityState());
        }
      }
      if (kIsWeb) whatsappWeb = await Native.whatsappWebState();
      apps = await Native.installedApps();
      batteryUnrestricted = await Native.isIgnoringBatteryOptimizations();
      isXiaomi = await Native.isXiaomi();
    } catch (e) {
      debugPrint('MobiWA status refresh failed: $e');
    } finally {
      _refreshing = false;
    }
    loaded = true;
    notifyListeners();
  }

  /// Fresh check right before an action starts (restarts a stopped service
  /// when possible). Returns true when the automation is running.
  Future<bool> ensureAutomation() async {
    await refresh();
    return accessibilityOn;
  }

  static AutomationState _parse(String s) => switch (s) {
        'running' => AutomationState.running,
        'stopped' => AutomationState.stopped,
        _ => AutomationState.off,
      };
}
