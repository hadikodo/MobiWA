import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../data/models.dart';
import 'web_bridge_stub.dart' if (dart.library.js_interop) 'web_bridge.dart';

/// Result of reading one chat.
class ChatRead {
  final bool notOnWhatsApp;
  final List<ChatMessage> messages;
  const ChatRead(this.notOnWhatsApp, this.messages);
}

/// The automation layer, one API for both platforms:
/// - Android: MainActivity + accessibility service (MethodChannel).
/// - Web: the MobiWA Connector Chrome extension working in WhatsApp Web.
class Native {
  Native._();

  static const _ch = MethodChannel('com.mobiwha/automation');
  static final _stop = StreamController<void>.broadcast();
  static final _scanProgress = StreamController<int>.broadcast();

  /// Fires when the user taps STOP (floating pill on Android, bar in WhatsApp Web).
  static Stream<void> get stopRequests => _stop.stream;
  static Stream<int> get scanProgress => _scanProgress.stream;

  static void init() {
    if (kIsWeb) {
      WebBridge.init();
      WebBridge.events.listen((e) {
        switch (e.event) {
          case 'stop':
            _stop.add(null);
          case 'scanProgress':
            _scanProgress.add((e.data as num?)?.toInt() ?? 0);
        }
      });
      return;
    }
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onStopRequested':
          _stop.add(null);
        case 'onScanProgress':
          _scanProgress.add(call.arguments as int);
      }
    });
  }

  // ------------------------------------------------------------- status

  static Future<List<WaApp>> installedApps() async {
    // On the web, WhatsApp Web uses whichever account (normal or Business) is linked.
    if (kIsWeb) return [WaApp.normal];
    try {
      final list = await _ch.invokeListMethod<String>('getInstalledApps') ?? [];
      return list.map(WaApp.fromPackage).whereType<WaApp>().toList();
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Android: "running", "stopped" (on in Settings, killed by the phone) or "off".
  /// Web: "running" (extension + WhatsApp Web ready), "stopped" (extension
  /// installed but WhatsApp Web closed / not linked) or "off" (no extension).
  static Future<String> accessibilityState() async {
    if (kIsWeb) {
      try {
        final r = await WebBridge.call('status', const {}, const Duration(milliseconds: 1500));
        final whatsapp = r is Map ? r['whatsapp'] : null;
        return whatsapp == 'ready' ? 'running' : 'stopped';
      } catch (_) {
        return 'off';
      }
    }
    try {
      return await _ch.invokeMethod<String>('getAccessibilityState') ?? 'off';
    } on PlatformException {
      return 'off';
    } on MissingPluginException {
      return 'off';
    }
  }

  /// Web only: what's missing in WhatsApp Web ("ready", "login", "closed").
  static Future<String> whatsappWebState() async {
    if (!kIsWeb) return 'ready';
    try {
      final r = await WebBridge.call('status', const {}, const Duration(milliseconds: 1500));
      return r is Map ? '${r['whatsapp']}' : 'closed';
    } catch (_) {
      return 'no_extension';
    }
  }

  /// Restarts a stopped service. Only works after the one-time adb grant of
  /// WRITE_SECURE_SETTINGS; returns false otherwise.
  static Future<bool> tryRestartAccessibility() async {
    if (kIsWeb) return false;
    try {
      return await _ch.invokeMethod<bool>('tryRestartAccessibility') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<({String id, String name})> deviceInfo() async {
    if (kIsWeb) {
      // A random id per browser profile, kept in local storage.
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('web_device_id');
      if (id == null) {
        final r = Random.secure();
        id = 'web-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        await prefs.setString('web_device_id', id);
      }
      return (id: id, name: 'Web · ${WebBridge.browserName()}');
    }
    try {
      final m = await _ch.invokeMapMethod<String, String>('getDeviceInfo') ?? const {};
      return (id: m['id'] ?? '', name: m['name'] ?? 'Android phone');
    } catch (_) {
      return (id: '', name: 'Unknown device');
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      return await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() =>
      _ch.invokeMethod('requestIgnoreBatteryOptimizations');

  static Future<void> openAutostartSettings() => _ch.invokeMethod('openAutostartSettings');

  static Future<bool> isXiaomi() async {
    if (kIsWeb) return false;
    try {
      return await _ch.invokeMethod<bool>('isXiaomi') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------- contacts (Android only)

  /// "granted", "denied" or "blocked" (only fixable in App info → Permissions).
  static Future<String> requestContactsPermission() async =>
      await _ch.invokeMethod<String>('requestContactsPermission') ?? 'denied';

  static Future<void> openAppSettings() => _ch.invokeMethod('openAppSettings');

  /// Saved contacts from the phone's address book, marked when on WhatsApp.
  static Future<List<PhoneContact>> phoneContacts() async {
    final list = await _ch.invokeListMethod<Map>('getPhoneContacts') ?? const [];
    return list.map(PhoneContact.fromMap).toList();
  }

  /// Android: Accessibility settings. Web: the extension install page.
  static Future<void> openAccessibilitySettings() async {
    if (kIsWeb) {
      await launchUrl(Uri.parse(Config.extensionUrl), webOnlyWindowName: '_blank');
      return;
    }
    await _ch.invokeMethod('openAccessibilitySettings');
  }

  static Future<void> openWhatsAppWeb() async {
    try {
      await WebBridge.call('openWhatsApp', const {}, const Duration(seconds: 5));
    } catch (_) {
      await launchUrl(Uri.parse('https://web.whatsapp.com'), webOnlyWindowName: '_blank');
    }
  }

  // ------------------------------------------------------------- actions

  /// Scrolls the WhatsApp chat list and returns unsaved numbers ("+digits").
  static Future<List<String>> scanUnsaved(WaApp app) async {
    if (kIsWeb) {
      final r = await WebBridge.call('scanUnsaved', const {}, const Duration(minutes: 20));
      return (r as List? ?? const []).map((e) => '$e').toList();
    }
    return await _ch.invokeListMethod<String>('scanUnsaved', {'package': app.package}) ?? [];
  }

  static Future<ChatRead> readChat(String phone, WaApp app) async {
    final Map? r = kIsWeb
        ? await WebBridge.call('readChat', {'phone': phone}, const Duration(seconds: 90)) as Map?
        : await _ch.invokeMapMethod<String, dynamic>(
            'readChat', {'phone': phone, 'package': app.package});
    final raw = (r?['messages'] as List?) ?? const [];
    return ChatRead(
      r?['status'] == 'not_on_whatsapp',
      [
        for (final m in raw.cast<Map>())
          (
            text: '${m['text'] ?? ''}',
            fromCustomer: m['direction'] != 'out',
            time: '${m['time'] ?? ''}',
          ),
      ],
    );
  }

  /// Returns "sent", "not_on_whatsapp", "cancelled" or "failed:<reason>".
  static Future<String> sendMessage({
    required String phone,
    required WaApp app,
    required String text,
    PickedMedia? media,
  }) async {
    if (kIsWeb) {
      try {
        final r = await WebBridge.call(
          'sendMessage',
          {
            'phone': phone,
            'text': text,
            if (media != null)
              'media': {
                'name': media.name,
                'mime': media.mime,
                'base64': base64Encode(media.bytes!),
              },
          },
          const Duration(minutes: 2),
        );
        return '$r';
      } on TimeoutException {
        return 'failed:timeout';
      } catch (e) {
        return 'failed:${e.toString().replaceFirst('Exception: ', '')}';
      }
    }
    return await _ch.invokeMethod<String>('sendMessage', {
          'phone': phone,
          'package': app.package,
          'text': text,
          if (media != null) 'mediaPath': media.path,
          if (media != null) 'mimeType': media.mime,
        }) ??
        'failed:no_result';
  }

  static Future<void> cancelJob() => kIsWeb ? _web('cancel') : _ch.invokeMethod('cancelJob');

  static Future<void> showOverlay(String text) =>
      kIsWeb
          ? _web('overlay', {'text': text, 'start': true}) // starts a run (clears STOP)
          : _ch.invokeMethod('showOverlay', {'text': text});

  static Future<void> updateOverlay(String text) =>
      kIsWeb ? _web('overlay', {'text': text}) : _ch.invokeMethod('updateOverlay', {'text': text});

  static Future<void> hideOverlay() =>
      kIsWeb ? _web('overlay', {'hide': true}) : _ch.invokeMethod('hideOverlay');

  static Future<void> returnToApp() => kIsWeb ? _web('focusApp') : _ch.invokeMethod('returnToApp');

  /// Fire-and-forget extension calls (status bar, focus); never throw.
  static Future<void> _web(String method, [Map<String, Object?> args = const {}]) async {
    try {
      await WebBridge.call(method, args, const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> openChat(String phone, {WaApp? app}) async {
    if (kIsWeb) {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      await launchUrl(Uri.parse('https://web.whatsapp.com/send?phone=$digits'),
          webOnlyWindowName: 'whatsapp');
      return;
    }
    await _ch.invokeMethod('openChat', {'phone': phone, if (app != null) 'package': app.package});
  }

  static Future<PickedMedia?> pickMedia(MessageType type) async {
    if (kIsWeb) {
      final f = await WebBridge.pickFile(type.pickerMime);
      if (f == null) return null;
      if (f.size > 64 * 1024 * 1024) throw Exception('File is larger than 64 MB.');
      return PickedMedia(path: '', name: f.name, mime: f.mime, size: f.size, bytes: f.bytes);
    }
    final r = await _ch.invokeMapMethod<String, dynamic>('pickMedia', {'mime': type.pickerMime});
    if (r == null) return null;
    return PickedMedia(
      path: r['path'] as String,
      name: r['name'] as String,
      mime: r['mime'] as String,
      size: (r['size'] as num).toInt(),
    );
  }
}
