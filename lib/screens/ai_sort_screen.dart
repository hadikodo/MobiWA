import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/phone.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../widgets/common.dart';
import '../widgets/phone_contact_picker.dart';
import 'send_screen.dart';

/// Step 2: AI opens each chat, reads it and files the number into a customer
/// category (named after what they asked for) or Junk.
/// Source: the Unnamed numbers, or contacts saved on the phone.
class AiSortScreen extends StatelessWidget {
  const AiSortScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final job = Job.sort;
    return Watch(
      listenables: [job, Db.revision, AppStatus.instance],
      builder: (context) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && job.finished) job.reset();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('AI Sort')),
          body: SafeArea(
            child: job.running || job.finished
                ? _Progress(job: job)
                : FutureBuilder<int>(
                    future: Db.count(Db.unnamedId),
                    builder: (context, snap) => _Start(unnamed: snap.data ?? 0),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _Source { unnamed, contacts }

class _Start extends StatefulWidget {
  const _Start({required this.unnamed});
  final int unnamed;

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  _Source _source = _Source.unnamed;
  List<PhoneContact> _picked = [];
  WaApp? _app;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    Settings.lastApp().then((last) {
      final installed = AppStatus.instance.apps;
      if (!mounted) return;
      setState(() => _app = (last != null && installed.contains(last))
          ? last
          : (installed.isNotEmpty ? installed.first : null));
    }, onError: (_) {});
  }

  Future<void> _pick() async {
    final r = await pickPhoneContacts(
      context,
      initial: _picked.map((c) => c.phone).toSet(),
      confirmLabel: 'Use these',
    );
    if (r != null) setState(() => _picked = r);
  }

  Future<bool> _ready() async {
    if (!await AppStatus.instance.ensureAutomation()) {
      if (mounted) showSnack(context, automationOffMessage());
      return false;
    }
    if (!mounted) return false;
    if (Job.active != null) {
      showSnack(context, 'Please wait: ${Job.active!.title.toLowerCase()} is still running.');
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      if (!await _ready()) return;
      if (_source == _Source.unnamed) {
        await Job.sort.start();
        return;
      }
      final app = _app;
      if (app == null) return;
      // Normalise numbers (local ones need the country code from Settings).
      final cc = await Settings.countryCode();
      final items = <({String phone, String name})>[];
      var invalid = 0;
      for (final c in _picked) {
        final n = Phone.normalize(c.phone, defaultCountryCode: cc);
        if (n == null) {
          invalid++;
        } else {
          items.add((phone: n, name: c.name));
        }
      }
      if (items.isEmpty) {
        if (mounted) {
          showSnack(context, 'None of these numbers has a country code. Set yours in Settings.');
        }
        return;
      }
      if (invalid > 0 && mounted) {
        showSnack(context,
            '$invalid contacts skipped: number without country code (set yours in Settings).');
      }
      final rows = await Db.importPhoneContacts(items, app.package);
      await Settings.setLastApp(app);
      await Job.sort.start(only: rows, app: app);
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStatus.instance;
    final cs = Theme.of(context).colorScheme;
    final unnamed = widget.unnamed;
    final isContacts = _source == _Source.contacts;
    final count = isContacts ? _picked.length : unnamed;
    final canStart = !_starting && count > 0 && (!isContacts || _app != null);
    final preview = _picked.take(3).map((c) => c.label).join(', ');

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s.loaded && !s.accessibilityOn) ...[
                const SetupCard(),
                const SizedBox(height: 16),
              ],
              const StepHeader(number: 1, title: 'What should the AI sort?'),
              _SourceOption(
                selected: !isContacts,
                icon: Icons.help_outline_rounded,
                color: AppColors.unnamed,
                title: 'Unnamed numbers',
                subtitle: unnamed == 0
                    ? 'Empty. Use Get Numbers to collect unsaved numbers'
                    : '$unnamed unsaved numbers waiting',
                onTap: () => setState(() => _source = _Source.unnamed),
              ),
              // Phone address book: Android only (browsers can't read it).
              if (!kIsWeb) const SizedBox(height: 10),
              if (!kIsWeb)
                _SourceOption(
                  selected: isContacts,
                  icon: Icons.contacts_rounded,
                  color: AppColors.scan,
                  title: 'My contacts',
                  subtitle: 'Contacts saved on your phone or on WhatsApp',
                  onTap: () => setState(() => _source = _Source.contacts),
                ),
              if (isContacts) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_rounded),
                    title: Text(
                        _picked.isEmpty ? 'Choose contacts' : '${_picked.length} contacts chosen'),
                    subtitle: Text(_picked.isEmpty
                        ? 'Pick from your phone (filter: on WhatsApp)'
                        : (_picked.length > 3 ? '$preview…' : preview)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pick,
                  ),
                ),
                const SizedBox(height: 20),
                const StepHeader(number: 2, title: 'Read their chats in'),
                WaAppPicker(selected: _app, onChanged: (a) => setState(() => _app = a)),
              ],
              const SectionTitle('How it works'),
              const _HowRow(
                  Icons.chat_outlined, 'Opens each chat in WhatsApp and reads the messages.'),
              const _HowRow(
                  Icons.shopping_bag_outlined,
                  'Customer? Files them into a category named after what they asked for, '
                  'e.g. "iPhone Repair". Existing categories are reused.'),
              const _HowRow(Icons.delete_outline_rounded,
                  'Not a customer (spam, wrong number, personal)? Moves them to Junk.'),
              if (isContacts)
                const _HowRow(Icons.badge_outlined,
                    'Saved names are kept. Contacts without a chat stay where they are.'),
              const _HowRow(Icons.lightbulb_outline_rounded,
                  'Tip: describe your business in Settings so the AI decides better.'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ai),
              onPressed: canStart ? _start : null,
              icon: _starting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(count == 0
                  ? (isContacts ? 'Choose contacts first' : 'Nothing to sort')
                  : 'Sort $count ${isContacts ? 'contacts' : 'numbers'}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppColors.ai.withValues(alpha: 0.08) : Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side:
            BorderSide(color: selected ? AppColors.ai : cs.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(icon, color, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppColors.ai : cs.outline),
          ]),
        ),
      ),
    );
  }
}

class _HowRow extends StatelessWidget {
  const _HowRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.ai),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.job});
  final SortJob job;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = job.total == 0 ? 0.0 : job.done / job.total;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.running
                              ? (job.stopRequested
                                  ? 'Stopping…'
                                  : 'Sorting ${job.done + 1} of ${job.total}')
                              : job.error != null
                                  ? 'Stopped'
                                  : 'All done',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text('${(pct * 100).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ai)),
                    ],
                  ),
                  if (job.running && job.current.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Reading ${job.current}',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 10,
                      color: AppColors.ai,
                      backgroundColor: AppColors.ai.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat('Customers', job.count(SortOutcome.customer), AppColors.success),
                      _Stat('Junk', job.count(SortOutcome.junk), AppColors.junk),
                      _Stat(
                          'Skipped',
                          job.count(SortOutcome.skipped) + job.count(SortOutcome.failed),
                          AppColors.unnamed),
                    ],
                  ),
                  if (job.error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                        const SizedBox(width: 10),
                        Expanded(child: Text(job.error!)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: job.log.isEmpty
              ? Center(
                  child: Text('Results will appear here…',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: job.log.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _LogTile(job.log[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: job.running
                ? OutlinedButton.icon(
                    onPressed: job.stopRequested ? null : job.stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(job.stopRequested ? 'Stopping…' : 'Stop'),
                  )
                : FilledButton.icon(
                    onPressed: () {
                      job.reset();
                      Navigator.of(context)
                          .pushReplacement(MaterialPageRoute(builder: (_) => const SendScreen()));
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Next: send messages'),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _LogTile extends StatelessWidget {
  const _LogTile(this.e);
  final SortLogEntry e;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (e.outcome) {
      SortOutcome.customer => (Icons.sell_rounded, AppColors.forCategory(e.detail), e.detail),
      SortOutcome.junk => (Icons.delete_outline_rounded, AppColors.junk, 'Junk'),
      SortOutcome.skipped => (Icons.skip_next_rounded, AppColors.unnamed, 'Kept in Unnamed'),
      SortOutcome.failed => (Icons.error_outline_rounded, AppColors.danger, 'Failed — will retry'),
    };
    return Card(
      child: ListTile(
        leading: IconTile(icon, color, size: 40),
        title: Text(e.phone, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          e.outcome == SortOutcome.customer ? '→ $title' : '$title · ${e.detail}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
