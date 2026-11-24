import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/jobs.dart';
import '../../widgets/common.dart';
import '../../widgets/live_data.dart';
import '../category_screen.dart';
import 'user_form.dart';

/// One user as seen by an admin: profile, business info, totals, categories,
/// and account actions (edit, disable, delete).
class AdminUserScreen extends StatefulWidget {
  const AdminUserScreen({super.key, required this.userId});
  final String userId;

  @override
  State<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends State<AdminUserScreen> {
  Future<(UserStats?, List<ContactCategory>)> _load() async {
    final all = await AdminApi.userStats();
    final stats = all.where((u) => u.profile.id == widget.userId).firstOrNull;
    final cats = stats == null ? <ContactCategory>[] : await Db.categories(userId: widget.userId);
    return (stats, cats);
  }

  bool get _isSelf => widget.userId == Auth.profile.value?.id;

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  Future<void> _toggleActive(Profile p) async {
    if (p.active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Disable ${p.displayName}?'),
          content: const Text('They are signed out and can\'t sign in until you enable them again. '
              'Their numbers are kept.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disable')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => AdminApi.updateUser(p.id, active: !p.active),
        p.active ? 'User disabled' : 'User enabled');
  }

  Future<void> _forceLogout(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text('Sign ${p.displayName} out?'),
        content: Text(
          'They are signed out of ${p.deviceName.isEmpty ? 'their phone' : p.deviceName} '
          '(within a minute, or right away when they open the app) and can then sign in '
          'from any phone. Their numbers are kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => AdminApi.forceLogout(p.id), '${p.displayName} was signed out');
  }

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${p.displayName}?'),
        content: const Text(
            'The account, all their numbers, categories and history are deleted for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminApi.deleteUser(p.id);
      if (mounted) {
        Navigator.of(context).pop();
        showSnack(context, 'User deleted');
      }
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('User')),
      body: LiveData<(UserStats?, List<ContactCategory>)>(
        load: _load,
        builder: (context, data, reload) {
          final (stats, cats) = data;
          if (stats == null) {
            return const EmptyState(icon: Icons.person_off_outlined, title: 'User not found');
          }
          final p = stats.profile;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                            foregroundColor: AppColors.brand,
                            child: Text(p.displayName.characters.first.toUpperCase(),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${p.isAdmin ? 'Admin' : 'User'} · ${p.active ? 'Active' : 'Disabled'}',
                                  style: TextStyle(
                                      color: p.active ? AppColors.success : AppColors.danger,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  p.lastSeenAt == null
                                      ? 'Never signed in'
                                      : 'Last seen ${_ago(p.lastSeenAt!)}',
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const Divider(height: 28),
                        // ------------------------------------------- device
                        Row(children: [
                          Icon(p.signedIn ? Icons.smartphone_rounded : Icons.phonelink_off_rounded,
                              color: p.signedIn ? AppColors.success : muted, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.signedIn
                                      ? 'Signed in on ${p.deviceName.isEmpty ? 'a phone' : p.deviceName}'
                                      : 'Not signed in on any phone',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  p.signedIn
                                      ? 'Since ${_ago(p.deviceBoundAt!)}'
                                          '${p.isAdmin ? ' · admins may use several phones' : ''}'
                                      : 'Can sign in from any phone',
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                          if (p.signedIn && !_isSelf)
                            FilledButton.tonalIcon(
                              onPressed: () => _forceLogout(p),
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Sign out'),
                            ),
                        ]),
                        const Divider(height: 28),
                        const Text('Business', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(p.businessName.isEmpty ? 'No business name' : p.businessName),
                        if (p.businessDescription.isNotEmpty)
                          Text(p.businessDescription, style: TextStyle(color: muted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showUserForm(context, existing: p),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  if (!_isSelf) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleActive(p),
                        icon: Icon(p.active ? Icons.block_rounded : Icons.check_circle_outline,
                            size: 18),
                        label: Text(p.active ? 'Disable' : 'Enable'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Delete user',
                      onPressed: () => _delete(p),
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _MiniStat('Numbers', stats.numbers, AppColors.unnamed),
                  _MiniStat('Customers', stats.customers, AppColors.ai),
                  _MiniStat('Junk', stats.junk, AppColors.junk),
                  _MiniStat('Sent', stats.messagesSent, AppColors.send),
                ]),
                SectionTitle('Categories · ${cats.length}'),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: IconTile(categoryLook(c).icon, categoryLook(c).color, size: 40),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: c.description.isEmpty
                            ? null
                            : Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${c.count}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Icon(Icons.chevron_right_rounded),
                        ]),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CategoryScreen(categoryId: c.id))),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}
