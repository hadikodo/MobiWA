import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session in Android's Keystore-encrypted storage instead
/// of plain SharedPreferences (Android only; the web uses browser storage
/// protected by the site's Content-Security-Policy).
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = 'mobiwa_session';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _read()) != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  Future<String?> _read() async {
    try {
      final v = await _storage.read(key: _key);
      if (v == null) return null;
      jsonDecode(v); // corrupted value → treat as signed out
      return v;
    } catch (_) {
      await _storage.delete(key: _key).catchError((_) {});
      return null;
    }
  }
}

/// Small secret values (the device token) in the same encrypted storage.
class SecureValues {
  SecureValues._();

  static const _storage = FlutterSecureStorage();

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {}
  }
}
