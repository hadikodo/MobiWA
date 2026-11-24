import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/native.dart';

/// This phone's identity for "one account = one device".
///
/// - [id] (Android ID) recognises the same phone again, even after a reinstall.
/// - [token] is the secret the server issues when this phone claims the
///   account. It is sent with every request ("x-device-token"); the database
///   only returns or changes data for the device holding the current token.
class Device {
  Device._();

  static const _tokenKey = 'device_token';
  static const _header = 'x-device-token';

  static String id = '';
  static String name = 'Android phone';
  static String? token;

  /// Loads id, name and the saved token, and attaches the token to requests.
  static Future<void> load() async {
    final info = await Native.deviceInfo();
    id = info.id;
    name = info.name;
    token = (await SharedPreferences.getInstance()).getString(_tokenKey);
    _apply();
  }

  static Future<void> setToken(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
    _apply();
  }

  /// Adds/removes the header on the REST and Edge Function clients in place
  /// (keeps their API key and auth headers untouched).
  static void _apply() {
    final c = Supabase.instance.client;
    for (final headers in [c.rest.headers, c.functions.headers]) {
      if (token == null) {
        headers.remove(_header);
      } else {
        headers[_header] = token!;
      }
    }
  }
}
