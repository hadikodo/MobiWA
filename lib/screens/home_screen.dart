import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../main.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../widgets/common.dart';
import 'ai_sort_screen.dart';
import 'category_screen.dart';
import 'get_numbers_screen.dart';
import 'send_progress_screen.dart';
import 'send_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _openJob(BuildContext context, Job job) => _open(
      context,
      switch (job) {
        ScanJob() => const GetNumbersScreen(),
        SortJob() => const AiSortScreen(),
        _ => const SendProgressScreen(),
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Watch(
          listenables: [Db.revision, AppStatus.instance],
          builder: (context) => FutureBuilder<List<ContactCategory>>(
            future: Db.categories(),
            builder: (context, snap) {
              final cats = snap.data ?? const <ContactCategory>[];
              final unnamed =
                  cats.where((c) => c.kind == CategoryKind.unnamed).firstOrNull?.count ?? 0;
              final customers = cats
                  .where((c) => c.kind == CategoryKind.custom)
                  .fold<int>(0, (sum, c) => sum + c.count);
              final status = AppStatus.instance;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _Header(total: cats.fold(0, (s, c) => s + c.count), customers: customers),
                  const SizedBox(height: 16),
                  ActiveJobBanner(onTap: (j) => _openJob(context, j)),
                  if (status.loaded && !status.ready)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: SetupCard(),
                    ),
                  const SectionTitle('What do you want to do?'),
                  ActionCard(
                    step: 1,
                    icon: Icons.person_search_rounded,
                    color: AppColors.scan,
                    title: 'Get Numbers',
                    subtitle: 'Collect every unsaved number from your WhatsApp chats.',
                    onTap: () => _open(context, const GetNumbersScreen()),
                  ),
                  const SizedBox(height: 12),
                  ActionCard(
                    step: 2,
                    icon: Icons.auto_awesome_rounded,
                    color: AppColors.ai,
                    title: 'AI Sort',
                    subtitle: 'AI reads the chats of your unsaved numbers or saved contacts and '
                        'files customers by what they asked for. The rest go to Junk.',
                    badge: unnamed > 0 ? '$unnamed waiting in Unnamed' : null,
                    onTap: () => _open(context, const AiSortScreen()),
                  ),
                  const SizedBox(height: 12),
                  ActionCard(
                    step: 3,
                    icon: Icons.send_rounded,
                    color: AppColors.send,
                    title: 'Send Messages',
                    subtitle: 'Send text, photos, videos or PDFs to numbers and categories '
                        'automatically.',
                    onTap: () => _open(context, const SendScreen()),
                  ),
                  if (cats.isNotEmpty) ...[
                    SectionTitle('Your categories',
                        trailing: TextButton(
                            onPressed: () => Shell.goTo(context, 1), child: const Text('See all'))),
                    _CategoryStrip(
                      categories: cats.where((c) => c.count > 0 || c.isSystem).take(8).toList(),
                      onTap: (c) => _open(context, CategoryScreen(categoryId: c.id)),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.customers});
  final int total;
  final int customers;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Image.asset('assets/images/logo.png', width: 44, height: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MobiWA', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                total == 0
                    ? 'Start with step 1 to collect your numbers'
                    : '$total numbers · $customers customers',
                style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories, required this.onTap});
  final List<ContactCategory> categories;
  final ValueChanged<ContactCategory> onTap;

  @override
  Widget build(BuildContext context) {
    // Fixed-height tiles, as many columns as fit (2 on phones, 4+ on desktop).
    return GridView(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 64,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final c in categories)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onTap(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconTile(categoryLook(c).icon, categoryLook(c).color, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${c.count}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
