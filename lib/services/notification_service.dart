// lib/services/notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'database_service.dart';
import 'contact_service.dart';
import '../models/lead.dart';

class NotificationService {
  static const _methodChannel = MethodChannel('com.mobiwha/control');
  static const _eventChannel = EventChannel('com.mobiwha/notifications');

  static StreamSubscription? _subscription;
  static final StreamController<Lead> _leadsController = StreamController.broadcast();

  /// Stream of newly captured leads (for real-time UI updates)
  static Stream<Lead> get newLeads => _leadsController.stream;

  /// Check if the NotificationListenerService permission is granted
  static Future<bool> hasPermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasNotificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Notification Access settings
  static Future<void> openSettings() async {
    await _methodChannel.invokeMethod('openNotificationSettings');
  }

  /// Check battery optimization exemption
  static Future<bool> isBatteryOptimized() async {
    try {
      return !(await _methodChannel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Request battery optimization exemption
  static Future<void> requestBatteryExemption() async {
    await _methodChannel.invokeMethod('requestBatteryOptimizationExemption');
  }

  /// Get WhatsApp backup paths from native side
  static Future<List<String>> getBackupPaths() async {
    try {
      final result = await _methodChannel.invokeMethod<List>('getWhatsAppBackupPaths');
      return result?.cast<String>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Start listening to the EventChannel for real-time notifications
  static void startListening() {
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) async {
        if (event == null) return;
        final str = event.toString();

        // Handle bulk flush (JSON array) or single JSON object
        if (str.startsWith('[')) {
          final list = jsonDecode(str) as List;
          for (final item in list) {
            await _handlePayload(item as Map<String, dynamic>);
          }
        } else {
          try {
            await _handlePayload(jsonDecode(str) as Map<String, dynamic>);
          } catch (_) {}
        }
      },
      onError: (e) {
        // Channel error - keep trying
      },
    );
  }

  static Future<void> _handlePayload(Map<String, dynamic> payload) async {
    final sender = payload['sender'] as String? ?? '';
    final message = payload['message'] as String? ?? '';
    final timestamp = payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final isGroup = payload['isGroup'] as bool? ?? false;
    final packageName = payload['packageName'] as String? ?? 'com.whatsapp';

    if (sender.isEmpty || message.isEmpty) return;

    // Classify unsaved
    final isUnsaved = ContactService.isUnsaved(sender);

    final lead = Lead(
      sender: sender,
      message: message,
      timestamp: timestamp,
      isUnsaved: isUnsaved,
      isGroup: isGroup,
      source: 'notification',
      packageName: packageName,
    );

    final inserted = await DatabaseService.insertLead(lead);
    if (inserted) {
      _leadsController.add(lead);
    }
  }

  static void dispose() {
    _subscription?.cancel();
    _leadsController.close();
  }
}
