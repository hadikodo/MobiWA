import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../services/native.dart';

/// Google Play "prominent disclosure": shown in the app, before the system
/// permission / settings screen, explaining what is accessed and why.
/// Returns true when the user agreed (remembered, so it's shown once).
class Disclosures {
  Disclosures._();

  static Future<bool> _show(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String title,
    required List<String> points,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: Icon(icon, color: AppColors.brand, size: 32),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.brand),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p)),
                  ]),
                ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => launchUrl(Uri.parse(Config.privacyUrl),
                    mode: LaunchMode.externalApplication),
                child: const Text('Read the Privacy Policy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
        ],
      ),
    );
    if (ok == true) await prefs.setBool(key, true);
    return ok == true;
  }

  /// Before sending the user to Android's Accessibility settings.
  static Future<bool> accessibility(BuildContext context) => _show(
        context,
        key: 'disclosure_accessibility_v1',
        icon: Icons.accessibility_new_rounded,
        title: 'MobiWA uses the Accessibility service',
        points: const [
          'MobiWA uses Android\'s Accessibility service to work inside WhatsApp for you: '
              'scroll your chat list, open chats, read the messages on screen and press Send.',
          'It only acts when YOU start an action (Get Numbers, AI Sort or Send Messages), '
              'and only inside WhatsApp and WhatsApp Business. A STOP button is shown while it works.',
          'What it reads: phone numbers shown in your chat list, and the text of the chats you '
              'choose to sort. Chat text is sent to our AI only to decide the category and is '
              'not stored; the number, category and a short reason are saved to your account.',
          'It does not read passwords, other apps, or anything when no action is running.',
        ],
      );

  /// Before asking for the Contacts permission.
  static Future<bool> contacts(BuildContext context) => _show(
        context,
        key: 'disclosure_contacts_v1',
        icon: Icons.contacts_rounded,
        title: 'Access to your contacts',
        points: const [
          'MobiWA reads the names and phone numbers saved on this phone so you can pick '
              'contacts for AI Sort or as message recipients, and to show which ones use WhatsApp.',
          'Your address book is read on this phone only. Only the contacts you choose for '
              'AI Sort are saved to your MobiWA account (name and number).',
          'Contacts are never sold or shared with third parties.',
        ],
      );
}

/// Opens Android's Accessibility settings after the prominent disclosure.
/// (Web: opens the extension page; the extension store shows its own permissions.)
Future<void> openAutomationSettings(BuildContext context) async {
  if (kIsWeb) return Native.openAccessibilitySettings();
  if (await Disclosures.accessibility(context)) await Native.openAccessibilitySettings();
}

Future<void> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
