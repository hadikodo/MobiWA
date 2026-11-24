import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../services/native.dart';
import 'disclosures.dart';

/// Rebuilds whenever any of [listenables] changes.
class Watch extends StatelessWidget {
  const Watch({super.key, required this.listenables, required this.builder});
  final List<Listenable> listenables;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (c, _) => builder(c),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Rounded, tinted icon square.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, this.color, {super.key, this.size = 48});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// One of the three main actions on the home screen.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.step,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final int step;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconTile(icon, color, size: 56),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: color,
                      child: Text('$step',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: t.bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    if (badge != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge!,
                            style: t.labelMedium
                                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + color for a category.
({IconData icon, Color color}) categoryLook(ContactCategory c) => switch (c.kind) {
      CategoryKind.unnamed => (icon: Icons.help_outline_rounded, color: AppColors.unnamed),
      CategoryKind.junk => (icon: Icons.delete_outline_rounded, color: AppColors.junk),
      CategoryKind.custom => (icon: Icons.sell_outlined, color: AppColors.forCategory(c.name)),
    };

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Shows what's missing (Accessibility, WhatsApp) with one-tap fixes.
class SetupCard extends StatelessWidget {
  const SetupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStatus.instance;
    final cs = Theme.of(context).colorScheme;
    final items = kIsWeb ? _webItems(s) : <Widget>[
      _SetupRow(
        done: s.whatsappInstalled,
        title: 'WhatsApp installed',
        hint: 'Install WhatsApp or WhatsApp Business',
      ),
      _SetupRow(
        done: s.accessibilityOn,
        title: s.automation == AutomationState.stopped
            ? 'Automation was stopped by the phone'
            : 'Allow automation',
        hint: s.automation == AutomationState.stopped
            ? 'Open Accessibility → MobiWA Automation → switch Off, then On again'
            : 'Accessibility → Installed apps → MobiWA Automation → On',
        action: s.accessibilityOn
            ? null
            : FilledButton.tonal(
                onPressed: () => openAutomationSettings(context),
                child: Text(s.automation == AutomationState.stopped ? 'Fix' : 'Turn on')),
      ),
      if (s.isXiaomi || !s.batteryUnrestricted) const KeepAliveTips(compact: true),
    ];
    return Card(
      color: AppColors.unnamed.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.unnamed.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.rocket_launch_outlined, color: AppColors.unnamed),
              const SizedBox(width: 10),
              Text(s.ready ? 'All set' : 'Finish setup',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
                kIsWeb
                    ? 'The web app works through WhatsApp Web with a small Chrome extension.'
                    : 'A few one-time steps so MobiWA can work inside WhatsApp.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ...items,
          ],
        ),
      ),
    );
  }

  /// Web: extension installed → WhatsApp Web open and linked.
  static List<Widget> _webItems(AppStatus s) {
    final hasExtension = s.automation != AutomationState.off;
    return [
      _SetupRow(
        done: hasExtension,
        title: 'Install the MobiWA Connector',
        hint: 'Free browser extension that works inside WhatsApp Web. Reload this page after installing.',
        action: hasExtension
            ? null
            : const FilledButton.tonal(
                onPressed: Native.openAccessibilitySettings, child: Text('Install')),
      ),
      _SetupRow(
        done: s.accessibilityOn,
        title: 'Open WhatsApp Web',
        hint: s.whatsappWeb == 'login'
            ? 'Link WhatsApp Web to your phone (WhatsApp → Linked devices)'
            : 'Keep a web.whatsapp.com tab open in this browser',
        action: s.accessibilityOn || !hasExtension
            ? null
            : const FilledButton.tonal(onPressed: Native.openWhatsAppWeb, child: Text('Open')),
      ),
    ];
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.done,
    required this.title,
    required this.hint,
    this.action,
    this.optional = false,
  });
  final bool done;
  final String title;
  final String hint;
  final Widget? action;

  /// A recommended step the app can't check (shown with a tip icon).
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
                optional
                    ? Icons.tips_and_updates_outlined
                    : done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                color: optional
                    ? AppColors.unnamed
                    : done
                        ? AppColors.success
                        : Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                      )),
                  if (!done)
                    Text(hint,
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

/// Banner shown on the home screen while an action runs in the background.
class ActiveJobBanner extends StatelessWidget {
  const ActiveJobBanner({super.key, required this.onTap});
  final void Function(Job job) onTap;

  @override
  Widget build(BuildContext context) {
    return Watch(
      listenables: Job.all,
      builder: (context) {
        final job = Job.active;
        if (job == null) return const SizedBox.shrink();
        final progress = switch (job) {
          SortJob j when j.total > 0 => '${j.done} of ${j.total}',
          SendJob j => '${j.count(SendStatus.sent)} of ${j.recipients.length} sent',
          ScanJob j => '${j.foundSoFar} found',
          _ => '',
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTap(job),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('${job.title}… $progress',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    const Text('View', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lets the user choose WhatsApp or WhatsApp Business (big tappable cards).
class WaAppPicker extends StatelessWidget {
  const WaAppPicker({super.key, required this.selected, required this.onChanged});
  final WaApp? selected;
  final ValueChanged<WaApp> onChanged;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // The web app always uses the account linked in WhatsApp Web.
      return Card(
        child: ListTile(
          leading: const IconTile(Icons.language_rounded, AppColors.brand, size: 44),
          title: const Text('WhatsApp Web', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Uses the WhatsApp or WhatsApp Business account linked in your '
              'WhatsApp Web tab.'),
          trailing: Icon(
            AppStatus.instance.accessibilityOn ? Icons.check_circle_rounded : Icons.error_outline,
            color: AppStatus.instance.accessibilityOn ? AppColors.success : AppColors.unnamed,
          ),
        ),
      );
    }
    final installed = AppStatus.instance.apps;
    return Row(
      children: [
        for (final app in WaApp.values) ...[
          Expanded(
            child: _AppOption(
              app: app,
              installed: installed.contains(app),
              selected: selected == app,
              onTap: () => onChanged(app),
            ),
          ),
          if (app != WaApp.values.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _AppOption extends StatelessWidget {
  const _AppOption({required this.app, required this.installed, required this.selected, required this.onTap});
  final WaApp app;
  final bool installed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const color = AppColors.brand;
    return Opacity(
      opacity: installed ? 1 : 0.45,
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? color : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: installed ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Column(
              children: [
                Icon(app == WaApp.business ? Icons.storefront_rounded : Icons.chat_rounded,
                    color: color, size: 32),
                const SizedBox(height: 8),
                Text(app.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(installed ? (selected ? 'Selected' : 'Tap to choose') : 'Not installed',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small numbered header used inside step-by-step screens.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.number, required this.title, this.subtitle});
  final int number;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.brand,
              child: Text('$number',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Phone settings that stop Android/MIUI from killing the automation service
/// (a killed service stays "crashed" until it is switched off and on again).
class KeepAliveTips extends StatelessWidget {
  const KeepAliveTips({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppStatus.instance;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'So the phone doesn\'t switch off MobiWA\'s automation in the background:',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
        _SetupRow(
          done: s.batteryUnrestricted,
          title: 'No battery restrictions',
          hint: 'Allow MobiWA to run in the background',
          action: s.batteryUnrestricted
              ? null
              : const FilledButton.tonal(
                  onPressed: Native.requestIgnoreBatteryOptimizations,
                  child: Text('Allow')),
        ),
        if (s.isXiaomi) ...[
          const _SetupRow(
            done: false,
            optional: true,
            title: 'Autostart (Xiaomi)',
            hint: 'Find MobiWA in the list and switch Autostart on',
            action: OutlinedButton(onPressed: Native.openAutostartSettings, child: Text('Open')),
          ),
          const _SetupRow(
            done: false,
            optional: true,
            title: 'Lock MobiWA in Recents',
            hint: 'Open Recents, long-press (or pull down) the MobiWA card → Lock, '
                'so "Clear all" doesn\'t close it',
          ),
        ],
      ],
    );
  }
}

String automationOffMessage() => AppStatus.instance.automation == AutomationState.stopped
    ? 'The phone stopped MobiWA Automation. In Accessibility, switch it off and on again.'
    : 'Turn on "MobiWA Automation" in Accessibility first.';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
