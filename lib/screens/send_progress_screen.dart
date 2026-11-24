import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/jobs.dart';
import '../widgets/common.dart';

/// Live progress of a sending run, and the summary when it ends.
class SendProgressScreen extends StatelessWidget {
  const SendProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final job = Job.send;
    return Watch(
      listenables: [job],
      builder: (context) {
        final total = job.recipients.length;
        final sent = job.count(SendStatus.sent);
        final processed = job.recipients
            .where((p) => job.status[p] != SendStatus.waiting && job.status[p] != SendStatus.sending)
            .length;
        final pct = total == 0 ? 0.0 : processed / total;
        final failedCount = job.failed.length;
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(title: Text(job.running ? 'Sending…' : 'Sending finished')),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 84,
                            height: 84,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: pct,
                                  strokeWidth: 8,
                                  color: AppColors.send,
                                  backgroundColor: AppColors.send.withValues(alpha: 0.15),
                                ),
                                Center(
                                  child: Text('$sent/$total',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800, fontSize: 18)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.running
                                      ? (job.stopRequested
                                          ? 'Stopping…'
                                          : job.secondsUntilNext > 0
                                              ? 'Next in ${job.secondsUntilNext}s'
                                              : 'Sending to ${job.index < total ? job.recipients[job.index] : ''}')
                                      : job.stopRequested
                                          ? 'Stopped'
                                          : 'Done',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$sent sent'
                                  '${job.count(SendStatus.notOnWhatsApp) > 0 ? ' · ${job.count(SendStatus.notOnWhatsApp)} not on WhatsApp' : ''}'
                                  '${failedCount > 0 ? ' · $failedCount failed' : ''}',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                                if (job.running) ...[
                                  const SizedBox(height: 6),
                                  Text('Keep the phone unlocked.',
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (job.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(job.error!, style: TextStyle(color: cs.error)),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: total,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = job.recipients[i];
                      return _Row(
                        phone: p,
                        status: job.status[p] ?? SendStatus.waiting,
                        reason: job.failReason[p],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: job.running
                      ? SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: job.stopRequested ? null : job.stop,
                            icon: const Icon(Icons.stop_rounded),
                            label: Text(job.stopRequested ? 'Stopping…' : 'Stop sending'),
                          ),
                        )
                      : Row(
                          children: [
                            if (failedCount > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: job.retryFailed,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text('Retry $failedCount'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  job.reset();
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.phone, required this.status, this.reason});
  final String phone;
  final SendStatus status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String label, Color color) = switch (status) {
      SendStatus.waiting => (
          const Icon(Icons.schedule_rounded, color: AppColors.junk),
          'Waiting',
          AppColors.junk
        ),
      SendStatus.sending => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          'Sending…',
          AppColors.brand
        ),
      SendStatus.sent => (
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          'Sent',
          AppColors.success
        ),
      SendStatus.notOnWhatsApp => (
          const Icon(Icons.block_rounded, color: AppColors.junk),
          'Not on WhatsApp',
          AppColors.junk
        ),
      SendStatus.failed => (
          const Icon(Icons.error_rounded, color: AppColors.danger),
          reason ?? 'Failed',
          AppColors.danger
        ),
      SendStatus.skipped => (
          const Icon(Icons.remove_circle_outline_rounded, color: AppColors.unnamed),
          'Not sent (stopped)',
          AppColors.unnamed
        ),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(width: 28, child: Center(child: icon)),
      title: Text(phone),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(label,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}
