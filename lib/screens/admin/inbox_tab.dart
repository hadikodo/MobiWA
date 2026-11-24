import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../data/models.dart';
import '../../services/jobs.dart';
import '../../widgets/common.dart';
import '../../widgets/disclosures.dart';
import '../../widgets/live_data.dart';

/// Admin: messages sent from the "Contact us" form on mobiwa.com.
class InboxTab extends StatelessWidget {
  const InboxTab({super.key});

  static const _topics = {
    'general': 'General',
    'sales': 'Sales',
    'support': 'Support',
    'account_deletion': 'Account deletion',
    'privacy': 'Privacy',
  };

  @override
  Widget build(BuildContext context) {
    return LiveData<List<ContactMessage>>(
      load: AdminApi.contactMessages,
      builder: (context, messages, reload) {
        if (messages.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No messages yet',
            message: 'Messages from the "Contact us" form on the website appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _MessageCard(messages[i], _topics),
          ),
        );
      },
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(this.m, this.topics);
  final ContactMessage m;
  final Map<String, String> topics;

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final urgent = m.topic == 'account_deletion' || m.topic == 'privacy';
    final d = m.createdAt.toLocal();
    final when = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Opacity(
      opacity: m.handled ? 0.6 : 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (urgent ? AppColors.danger : AppColors.scan).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(topics[m.topic] ?? m.topic,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: urgent ? AppColors.danger : AppColors.scan)),
                ),
                const SizedBox(width: 8),
              ]),
              Text(
                [m.email, if (m.business.isNotEmpty) m.business, when].join(' · '),
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 8),
              SelectableText(m.message),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => openLink('mailto:${m.email}?subject=Re: your message to MobiWA'),
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: const Text('Reply'),
                  ),
                  TextButton.icon(
                    onPressed: () => _run(context, () => AdminApi.setMessageHandled(m.id, !m.handled)),
                    icon: Icon(m.handled ? Icons.mark_email_unread_outlined : Icons.done_rounded,
                        size: 18),
                    label: Text(m.handled ? 'Reopen' : 'Done'),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _run(context, () => AdminApi.deleteMessage(m.id)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
