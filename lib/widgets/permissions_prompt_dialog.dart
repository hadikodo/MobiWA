// lib/widgets/permissions_prompt_dialog.dart
import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/whatsapp_service.dart';

class PermissionsPromptDialog extends StatefulWidget {
  const PermissionsPromptDialog({super.key});

  /// Checks if any critical permission is missing, and if so, shows the prompt dialog.
  static Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    final contactsOk = await ContactService.hasPermission();
    final notificationOk = await WhatsAppService.hasNotificationAccess();
    final accessibilityOk = await WhatsAppService.hasAccessibilityAccess();

    if (!contactsOk || !notificationOk || !accessibilityOk) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const PermissionsPromptDialog(),
      );
    }
  }

  @override
  State<PermissionsPromptDialog> createState() =>
      _PermissionsPromptDialogState();
}

class _PermissionsPromptDialogState extends State<PermissionsPromptDialog>
    with WidgetsBindingObserver {
  bool _contactsGranted = false;
  bool _notificationGranted = false;
  bool _accessibilityGranted = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final contacts = await ContactService.hasPermission();
    final notification = await WhatsAppService.hasNotificationAccess();
    final accessibility = await WhatsAppService.hasAccessibilityAccess();

    if (!mounted) return;
    setState(() {
      _contactsGranted = contacts;
      _notificationGranted = notification;
      _accessibilityGranted = accessibility;
      _isLoading = false;
    });
  }

  bool get _allGranted =>
      _contactsGranted && _notificationGranted && _accessibilityGranted;

  Future<void> _requestContacts() async {
    await ContactService.requestPermission();
    await _checkPermissions();
  }

  Future<void> _openNotificationSettings() async {
    await WhatsAppService.openNotificationAccessSettings();
  }

  Future<void> _openAccessibilitySettings() async {
    await WhatsAppService.openAccessibilitySettings();
  }

  Future<void> _openAppDetailsSettings() async {
    await WhatsAppService.openAppDetailsSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _isLoading
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _allGranted
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _allGranted
                                  ? Icons.verified_user_rounded
                                  : Icons.security_rounded,
                              color: _allGranted
                                  ? Colors.green.shade800
                                  : Colors.orange.shade900,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _allGranted
                                      ? 'All Permissions Granted'
                                      : 'Permissions Setup',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _allGranted
                                      ? 'Mobi AI is fully operational.'
                                      : 'Grant access to enable all AI features.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'To read chat history, profile customer leads, and automatically respond via WhatsApp, Mobi AI requires the following permissions:',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 1. Contacts
                      _PermissionItem(
                        icon: Icons.contacts_rounded,
                        title: 'Device Contacts',
                        subtitle:
                            'Identifies unsaved phone numbers and syncs WhatsApp leads.',
                        isGranted: _contactsGranted,
                        actionLabel: 'Allow',
                        onAction: _requestContacts,
                      ),
                      const SizedBox(height: 10),

                      // 2. Notification Access
                      _PermissionItem(
                        icon: Icons.notifications_active_rounded,
                        title: 'Notification Access',
                        subtitle:
                            'Required for AI Auto-Responder to detect and reply in background.',
                        isGranted: _notificationGranted,
                        actionLabel: 'Enable',
                        onAction: _openNotificationSettings,
                      ),
                      const SizedBox(height: 10),

                      // 3. Accessibility Service
                      _PermissionItem(
                        icon: Icons.touch_app_rounded,
                        title: 'WhatsApp Chat Reader',
                        subtitle:
                            'Enables Mobi AI to read chat history for automated profiling.',
                        isGranted: _accessibilityGranted,
                        actionLabel: 'Enable',
                        onAction: _openAccessibilitySettings,
                      ),
                      const SizedBox(height: 14),

                      // Xiaomi / Android 13+ helper banner
                      if (!_notificationGranted || !_accessibilityGranted)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.amber.shade900),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Xiaomi / Android 13+ Tip',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _openAppDetailsSettings,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: Text(
                                        'Open App Info',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'If Android says "Restricted setting", tap "Open App Info" -> tap the 3 dots (⋮) top-right -> "Allow restricted settings" -> then return here and enable.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade900,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 18),

                      // Actions
                      if (_allGranted)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text(
                            'All Set — Continue',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(
                                  'Continue Anyway',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () async {
                                  if (!_contactsGranted) {
                                    await _requestContacts();
                                  } else if (!_notificationGranted) {
                                    await _openNotificationSettings();
                                  } else if (!_accessibilityGranted) {
                                    await _openAccessibilitySettings();
                                  }
                                },
                                child: Text(
                                  !_contactsGranted
                                      ? 'Grant Contacts'
                                      : (!_notificationGranted
                                          ? 'Enable Notifications'
                                          : 'Enable Chat Reader'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGranted;
  final String actionLabel;
  final VoidCallback onAction;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGranted,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isGranted ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.shade100 : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isGranted ? Colors.green.shade800 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color:
                        isGranted ? Colors.green.shade900 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isGranted
                        ? Colors.green.shade800
                        : Colors.grey.shade600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.green.shade700, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Granted',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(60, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
