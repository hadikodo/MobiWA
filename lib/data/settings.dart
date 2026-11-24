import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'models.dart';

/// Per-device preferences. Business info lives on the user's profile in
/// Supabase (so the admin can see it); the Gemini key lives in Supabase secrets.
class Settings {
  Settings._();

  static const _delay = 'send_delay_seconds';
  static const _countryCode = 'default_country_code';
  static const _lastApp = 'last_whatsapp_app';

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  /// Business description from the profile; helps the AI tell customers from junk.
  static Future<String> business() async {
    final p = Auth.profile.value;
    if (p == null) return '';
    return [p.businessName, p.businessDescription].where((s) => s.isNotEmpty).join(' — ');
  }

  /// Seconds to wait between two messages when sending.
  static Future<int> sendDelay() async => (await _p).getInt(_delay) ?? 6;
  static Future<void> setSendDelay(int v) async => (await _p).setInt(_delay, v);

  /// Digits only, e.g. "961". Used for typed numbers starting with 0.
  static Future<String> countryCode() async => (await _p).getString(_countryCode) ?? '';
  static Future<void> setCountryCode(String v) async =>
      (await _p).setString(_countryCode, v.replaceAll(RegExp(r'\D'), ''));

  static Future<WaApp?> lastApp() async => WaApp.fromPackage((await _p).getString(_lastApp));
  static Future<void> setLastApp(WaApp a) async => (await _p).setString(_lastApp, a.package);
}
