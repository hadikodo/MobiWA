import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/auth.dart';
import '../data/db.dart';
import '../data/settings.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../widgets/common.dart';
import '../widgets/disclosures.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bizName = TextEditingController();
  final _bizDesc = TextEditingController();
  final _cc = TextEditingController();
  int _delay = 6;
  bool _savingBiz = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = Auth.profile.value;
    _bizName.text = p?.businessName ?? '';
    _bizDesc.text = p?.businessDescription ?? '';
    _cc.text = await Settings.countryCode();
    _delay = await Settings.sendDelay();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bizName.dispose();
    _bizDesc.dispose();
    _cc.dispose();
    super.dispose();
  }

  Future<void> _saveBusiness() async {
    setState(() => _savingBiz = true);
    try {
      await Auth.updateBusiness(name: _bizName.text, description: _bizDesc.text);
      if (mounted) showSnack(context, 'Business info saved');
    } catch (e) {
      if (mounted) showSnack(context, 'Not saved: ${Job.friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _savingBiz = false);
    }
  }

  Future<void> _signOut() async {
    if (Job.active != null) {
      showSnack(context, 'Wait for ${Job.active!.title.toLowerCase()} to finish first.');
      return;
    }
    await Auth.signOut();
  }

  Future<void> _deleteAccount() async {
    if (Job.active != null) {
      showSnack(context, 'Wait for ${Job.active!.title.toLowerCase()} to finish first.');
      return;
    }
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 32),
          title: const Text('Delete your account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your account, numbers, categories and history are deleted for good. '
                  'This cannot be undone.'),
              const SizedBox(height: 14),
              TextField(
                controller: confirm,
                autocorrect: false,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed:
                  confirm.text.trim().toUpperCase() == 'DELETE' ? () => Navigator.pop(c, true) : null,
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );
    confirm.dispose();
    if (ok != true) return;
    try {
      await Auth.deleteOwnAccount();
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all my numbers?'),
        content: const Text('All your numbers and customer categories are removed. '
            'WhatsApp is not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Db.clearAll();
      if (mounted) showSnack(context, 'All numbers deleted');
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Watch(
        listenables: [AppStatus.instance, Auth.profile],
        builder: (context) {
          final s = AppStatus.instance;
          final p = Auth.profile.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              // -------------------------------------------------- account
              const SectionTitle('Account'),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                    foregroundColor: AppColors.brand,
                    child: Text((p?.displayName ?? '?').characters.first.toUpperCase()),
                  ),
                  title: Text(p?.displayName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${p?.username ?? ''} · ${p?.isAdmin == true ? 'Admin' : 'User'}'),
                  trailing: TextButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out'),
                  ),
                ),
              ),

              // ------------------------------------------------- business
              const SectionTitle('My business'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _bizName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Business name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _bizDesc,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'What do you sell?',
                          hintText: 'e.g. Phone repair and accessories in Beirut',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('The AI uses this to tell real customers from junk.',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: _savingBiz ? null : _saveBusiness,
                          child: Text(_savingBiz ? 'Saving…' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------- permissions
              const SectionTitle(kIsWeb ? 'WhatsApp Web connection' : 'Permissions'),
              if (kIsWeb) const SetupCard() else Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: IconTile(Icons.accessibility_new_rounded,
                          s.accessibilityOn ? AppColors.success : AppColors.danger,
                          size: 40),
                      title: const Text('WhatsApp automation'),
                      subtitle: Text(switch (s.automation) {
                        AutomationState.running => 'On — MobiWA can work inside WhatsApp',
                        AutomationState.stopped => 'Stopped by the phone — switch it off and on again',
                        AutomationState.off => 'Off — needed for all 3 actions',
                      }),
                      trailing: s.accessibilityOn
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                          : FilledButton.tonal(
                              onPressed: () => openAutomationSettings(context),
                              child: Text(s.automation == AutomationState.stopped ? 'Fix' : 'Turn on')),
                    ),
                    if (!s.accessibilityOn)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Text(
                          s.automation == AutomationState.stopped
                              ? 'Android stopped the automation when MobiWA was closed in the '
                                  'background. Open Accessibility → MobiWA Automation, switch it Off, '
                                  'then On. The tips below stop this from happening again.'
                              : 'In Accessibility, open "Installed apps" (or "Downloaded apps"), choose '
                                  '"MobiWA Automation" and switch it on. If Android says the setting is '
                                  'restricted: App info → ⋮ → "Allow restricted settings", then try again.',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('Keep automation running',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 12, 8),
                      child: KeepAliveTips(),
                    ),
                    const Divider(),
                    ListTile(
                      leading: IconTile(Icons.chat_rounded,
                          s.whatsappInstalled ? AppColors.success : AppColors.danger,
                          size: 40),
                      title: const Text('WhatsApp apps found'),
                      subtitle: Text(s.apps.isEmpty
                          ? 'None installed'
                          : s.apps.map((a) => a.label).join(' · ')),
                    ),
                  ],
                ),
              ),

              // --------------------------------------------------- sending
              const SectionTitle('Sending (this phone)'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Wait between messages',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Text('$_delay s',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: AppColors.brand)),
                        ],
                      ),
                      Slider(
                        value: _delay.toDouble(),
                        min: 3,
                        max: 60,
                        divisions: 57,
                        label: '$_delay s',
                        onChanged: (v) => setState(() => _delay = v.round()),
                        onChangeEnd: (v) => Settings.setSendDelay(v.round()),
                      ),
                      Text(
                        'Longer pauses look more natural and lower the risk of WhatsApp '
                        'limiting your account.',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const Divider(height: 32),
                      TextField(
                        controller: _cc,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Your country code',
                          hintText: 'e.g. 961',
                          prefixText: '+',
                        ),
                        onChanged: Settings.setCountryCode,
                      ),
                      const SizedBox(height: 6),
                      Text('Used when you type local numbers like 70 123 456 or 03 123 456.',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),

              // ------------------------------------------------------ data
              const SectionTitle('Data'),
              Card(
                child: ListTile(
                  leading: const IconTile(Icons.delete_forever_outlined, AppColors.danger, size: 40),
                  title: const Text('Delete all my numbers'),
                  subtitle: const Text('Start fresh. Your account stays.'),
                  onTap: _clearAll,
                ),
              ),

              // ----------------------------------------------- about & legal
              const SectionTitle('About'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline_rounded),
                      title: Text('MobiWA'),
                      subtitle: Text('Version ${Config.appVersion}'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => openLink(Config.privacyUrl),
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_rounded),
                      title: const Text('Terms of Service'),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => openLink(Config.termsUrl),
                    ),
                    ListTile(
                      leading: const Icon(Icons.support_agent_rounded),
                      title: const Text('Contact support'),
                      subtitle: const Text(Config.supportEmail),
                      onTap: () => openLink('mailto:${Config.supportEmail}'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
                      title: const Text('Delete my account',
                          style: TextStyle(color: AppColors.danger)),
                      subtitle: const Text('Permanently deletes your account and all its data'),
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
