import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WhatsAppService {
  static const _channel =
      MethodChannel('com.mobiwha.mobiwha/notification_capture');
  static final pendingSharedChatExport =
      ValueNotifier<Map<String, String>?>(null);

  static Future<Map<String, String>?> takeSharedChatExport() =>
      _channel.invokeMapMethod<String, String>('takeSharedWhatsAppExport');

  static Future<void> checkForSharedChatExport() async {
    final export = await takeSharedChatExport();
    if (export != null) pendingSharedChatExport.value = export;
  }

  /// Opens Android's system document picker and reads a user-selected chat
  /// export as plain text. Returns null if the user cancels.
  static Future<Map<String, String>?> pickChatExport() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'pickWhatsAppChatExport',
    );
    return result;
  }

  /// Opens Android's multi-file document picker for selecting multiple chat
  /// exports at once. Returns a list of maps with 'name' and 'content' keys,
  /// or null if the user cancels.
  static Future<List<Map<String, String>>?> pickMultipleChatExports() async {
    final result = await _channel.invokeMethod('pickMultipleChatExports');
    if (result == null) return null;
    final list = (result as List).cast<Map>();
    return list
        .map((m) => Map<String, String>.from(m.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )))
        .toList();
  }

  static Future<bool> hasAccessibilityAccess() async {
    final result = await _channel.invokeMethod<bool>('hasAccessibilityAccess');
    return result ?? false;
  }

  static Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  /// Returns list of installed WhatsApp packages (standard and/or business)
  static Future<List<Map<String, String>>> getInstalledWhatsAppApps() async {
    final result = await _channel.invokeListMethod<Map>('getInstalledWhatsAppApps');
    if (result == null) return [];
    return result
        .map((m) => Map<String, String>.from(
              m.map((k, v) => MapEntry(k.toString(), v.toString())),
            ))
        .toList();
  }

  /// Starts automated WhatsApp chat list crawler for a specific app package.
  /// Automatically scrolls through WhatsApp chat list, extracts unsaved phone numbers,
  /// and returns the list of extracted numbers without any manual user action.
  static Future<List<String>> startAutoScanWhatsApp({String? packageName}) async {
    final result = await _channel.invokeListMethod<String>(
      'startAutoScanWhatsApp',
      packageName != null ? {'packageName': packageName} : null,
    );
    return result ?? <String>[];
  }

  /// Stops ongoing auto scan and returns MobiWA to front.
  static Future<void> stopAutoScanWhatsApp() async {
    await _channel.invokeMethod<void>('stopAutoScanWhatsApp');
  }

  /// Automatically opens a WhatsApp chat for a number, scrapes the last visible messages
  /// using Accessibility, and returns the list of parsed messages without sending any text.
  static Future<List<Map<String, String>>> scrapeChatMessages({
    required String phoneNumber,
    String? packageName,
  }) async {
    final result = await _channel.invokeListMethod<Map>('scrapeChatMessages', {
      'phone': phoneNumber,
      if (packageName != null) 'packageName': packageName,
    });
    if (result == null) return [];
    return result
        .map((m) => Map<String, String>.from(
              m.map((k, v) => MapEntry(k.toString(), v.toString())),
            ))
        .toList();
  }

  /// Opens WhatsApp with a prepared draft. The user reviews and sends it there.
  static Future<void> openChat({
    required String phoneNumber,
    String message = '',
  }) async {
    await _channel.invokeMethod<bool>('openWhatsAppChat', {
      'phone': phoneNumber,
      'message': message,
    });
  }
}
