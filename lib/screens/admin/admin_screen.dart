import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/live_data.dart';
import 'activity_chart.dart';
import 'inbox_tab.dart';
import 'admin_user_screen.dart';
import 'user_form.dart';

/// Admin tab: analytics for all users + user management.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(tabs: [Tab(text: 'Dashboard'), Tab(text: 'Users'), Tab(text: 'Inbox')]),
        ),
        body: const TabBarView(children: [_Dashboard(), _Users(), InboxTab()]),
      ),
    );
  }
}

void openUser(BuildContext context, String userId) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => AdminUserScreen(userId: userId)));

// ---------------------------------------------------------------- dashboard

class _Dashboard extends StatelessWidget {
  const _Dashboard();

  static Future<(List<UserStats>, List<DayActivity>)> _load() async {
    final r = await Future.wait([AdminApi.userStats(), AdminApi.dailyActivity(days: 14)]);
    return (r[0] as List<UserStats>, r[1] as List<DayActivity>);
  }

  @override
  Widget build(BuildContext context) {
    return LiveData<(List<UserStats>, List<DayActivity>)>(
      load: _load,
      builder: (context, data, reload) {
        final (users, days) = data;
        int sum(int Function(UserStats) f) => users.fold(0, (s, u) => s + f(u));
        final numbers = sum((u) => u.numbers);
        final customers = sum((u) => u.customers);
        final junk = sum((u) => u.junk);
        final sorted = customers + junk;
        final top = [...users]..sort((a, b) => b.numbers.compareTo(a.numbers));

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GridView(
                // 2 tiles per row on phones, 4 on wide screens.
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 118,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StatTile(
                    icon: Icons.group_rounded,
                    color: AppColors.scan,
                    value: '${users.length}',
                    label: 'Users',
                    note: '${users.where((u) => u.profile.active).length} active',
                  ),
                  _StatTile(
                    icon: Icons.pin_outlined,
                    color: AppColors.unnamed,
                    value: '$numbers',
                    label: 'Numbers collected',
                    note: '${sum((u) => u.unnamed)} waiting to sort',
                  ),
                  _StatTile(
                    icon: Icons.shopping_bag_outlined,
                    color: AppColors.ai,
                    value: '$customers',
                    label: 'Customers',
                    note: sorted == 0
                        ? 'none sorted yet'
                        : '${(customers * 100 / sorted).round()}% of sorted · $junk junk',
                  ),
                  _StatTile(
                    icon: Icons.send_rounded,
                    color: AppColors.send,
                    value: '${sum((u) => u.messagesSent)}',
                    label: 'Messages sent',
                    note: 'all time',
                  ),
                ],
              ),
              const SectionTitle('Last 14 days'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: ActivityChart(days: days),
                ),
              ),
              SectionTitle('Users by numbers',
                  trailing: Text('${users.length}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              for (final u in top.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _UserRow(u, onTap: () => openUser(context, u.profile.id)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.note,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w600)),
              ),
            ]),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text(note,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow(this.u, {required this.onTap});
  final UserStats u;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = u.profile;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: (p.active ? AppColors.brand : AppColors.junk).withValues(alpha: 0.15),
          foregroundColor: p.active ? AppColors.brand : AppColors.junk,
          child: Text(p.displayName.characters.first.toUpperCase()),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(p.displayName,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (p.isAdmin) const _Badge('Admin', AppColors.ai),
            if (!p.active) const _Badge('Disabled', AppColors.danger),
            if (p.active && p.signedIn) const _Badge('Online', AppColors.success),
          ],
        ),
        subtitle: Text(
          [
            if (p.businessName.isNotEmpty) p.businessName,
            '${u.numbers} numbers · ${u.customers} customers · ${u.messagesSent} sent',
            if (p.signedIn && p.deviceName.isNotEmpty) '📱 ${p.deviceName}',
          ].join('\n'),
          style: TextStyle(color: muted),
        ),
        isThreeLine: p.businessName.isNotEmpty || (p.signedIn && p.deviceName.isNotEmpty),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}

// -------------------------------------------------------------------- users

class _Users extends StatefulWidget {
  const _Users();

  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showUserForm(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add user'),
      ),
      body: LiveData<List<UserStats>>(
        load: AdminApi.userStats,
        builder: (context, users, reload) {
          final q = _q.toLowerCase();
          final list = users
              .where((u) =>
                  q.isEmpty ||
                  u.profile.username.contains(q) ||
                  u.profile.fullName.toLowerCase().contains(q) ||
                  u.profile.businessName.toLowerCase().contains(q))
              .toList();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search ${users.length} users',
                  ),
                ),
                const SizedBox(height: 12),
                for (final u in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _UserRow(u, onTap: () => openUser(context, u.profile.id)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
