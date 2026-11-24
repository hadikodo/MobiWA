import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../widgets/common.dart';
import 'ai_sort_screen.dart';
import 'category_screen.dart';

/// Step 1: choose WhatsApp or WhatsApp Business, then collect unsaved numbers.
class GetNumbersScreen extends StatefulWidget {
  const GetNumbersScreen({super.key});

  @override
  State<GetNumbersScreen> createState() => _GetNumbersScreenState();
}

class _GetNumbersScreenState extends State<GetNumbersScreen> {
  WaApp? _app;
  final job = Job.scan;

  @override
  void initState() {
    super.initState();
    _pickDefaultApp();
  }

  Future<void> _pickDefaultApp() async {
    final installed = AppStatus.instance.apps;
    final last = await Settings.lastApp();
    if (!mounted) return;
    setState(() {
      _app = job.app ??
          (last != null && installed.contains(last)
              ? last
              : (installed.length == 1 ? installed.first : null));
    });
  }

  Future<void> _start() async {
    final app = _app;
    if (app == null) return;
    if (!await AppStatus.instance.ensureAutomation()) {
      if (mounted) showSnack(context, automationOffMessage());
      return;
    }
    if (!mounted) return;
    if (Job.active != null) {
      showSnack(context, 'Please wait: ${Job.active!.title.toLowerCase()} is still running.');
      return;
    }
    await job.start(app);
  }

  @override
  Widget build(BuildContext context) {
    return Watch(
      listenables: [job, AppStatus.instance],
      builder: (context) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && job.finished) job.reset();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Get Numbers')),
          body: SafeArea(
            child: job.running
                ? _Running(job: job)
                : job.finished
                    ? _Done(job: job)
                    : _Start(
                        app: _app,
                        onApp: (a) => setState(() => _app = a),
                        onStart: _start,
                      ),
          ),
        ),
      ),
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.app, required this.onApp, required this.onStart});
  final WaApp? app;
  final ValueChanged<WaApp> onApp;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final status = AppStatus.instance;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (status.loaded && !status.accessibilityOn) ...[
                const SetupCard(),
                const SizedBox(height: 16),
              ],
              const StepHeader(
                number: 1,
                title: 'Which WhatsApp?',
                subtitle: 'Numbers will be collected from this app.',
              ),
              WaAppPicker(selected: app, onChanged: onApp),
              const SizedBox(height: 28),
              const StepHeader(number: 2, title: 'What happens next'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _Bullet(Icons.open_in_new_rounded,
                          'MobiWA opens WhatsApp and scrolls through all your chats.'),
                      _Bullet(Icons.pin_outlined,
                          'Every chat that shows a phone number instead of a name is an unsaved number.'),
                      _Bullet(Icons.folder_outlined,
                          'New numbers are added to the "Unnamed" category.'),
                      _Bullet(Icons.pan_tool_outlined,
                          'Don\'t touch the phone until it finishes. Tap STOP on the screen any time.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.scan),
              onPressed: app == null ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(app == null ? 'Choose a WhatsApp above' : 'Start collecting'),
            ),
          ),
        ),
        if (app == null && status.apps.isEmpty && status.loaded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('WhatsApp is not installed on this phone.',
                style: TextStyle(color: cs.error)),
          ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.scan),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Running extends StatelessWidget {
  const _Running({required this.job});
  final ScanJob job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 6)),
          const SizedBox(height: 28),
          Text('${job.foundSoFar}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          const Text('numbers found so far'),
          const SizedBox(height: 16),
          Text('MobiWA is scrolling through ${job.app?.label ?? 'WhatsApp'}.\n'
              'Please don\'t touch the phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: job.stopRequested ? null : job.stop,
            icon: const Icon(Icons.stop_rounded),
            label: Text(job.stopRequested ? 'Stopping…' : 'Stop'),
          ),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.job});
  final ScanJob job;

  @override
  Widget build(BuildContext context) {
    final failed = job.error != null;
    final already = job.found - job.added;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(failed ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              size: 80, color: failed ? AppColors.danger : AppColors.success),
          const SizedBox(height: 20),
          Text(
            failed
                ? 'Could not finish'
                : job.added == 0
                    ? 'No new numbers'
                    : '${job.added} new numbers added',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? job.error!
                : 'Found ${job.found} unsaved numbers'
                    '${already > 0 ? ' · $already were already in MobiWA' : ''}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (!failed && job.found > 0) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.ai),
                onPressed: () {
                  job.reset();
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AiSortScreen()));
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Next: sort them with AI'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CategoryScreen(categoryId: Db.unnamedId))),
                child: const Text('View Unnamed numbers'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: job.reset, child: const Text('Try again')),
            ),
        ],
      ),
    );
  }
}
