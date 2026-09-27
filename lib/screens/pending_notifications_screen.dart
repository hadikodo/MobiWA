import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../services/database_service.dart';

class PendingNotificationsScreen extends StatefulWidget {
  const PendingNotificationsScreen({super.key});

  @override
  State<PendingNotificationsScreen> createState() =>
      _PendingNotificationsScreenState();
}

class _PendingNotificationsScreenState
    extends State<PendingNotificationsScreen> {
  List<Map<String, Object?>> _pending = [];
  List<Lead> _leads = [];
  final Map<String, int?> _selectedLeads = {};
  bool _loading = true;
  final _dateFormat = DateFormat('MMM d, y • h:mm a');

  @override
  void initState() {
    super.initState();
    DatabaseService.dataRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DatabaseService.dataRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final results = await Future.wait([
      DatabaseService.getPendingNotifications(limit: 500),
      DatabaseService.getLeads(limit: 50000),
    ]);
    if (!mounted) return;
    final pending = results[0] as List<Map<String, Object?>>;
    final leads = results[1] as List<Lead>;
    final pendingKeys = pending
        .map((item) => item['notification_key']?.toString() ?? '')
        .toSet();
    _selectedLeads.removeWhere((key, _) => !pendingKeys.contains(key));
    setState(() {
      _pending = pending;
      _leads = leads.where((lead) => lead.id != null).toList();
      _loading = false;
    });
  }

  Future<void> _assign(Map<String, Object?> notification) async {
    final key = notification['notification_key']?.toString() ?? '';
    final leadId = _selectedLeads[key];
    if (key.isEmpty || leadId == null) return;
    final assigned = await DatabaseService.assignPendingNotificationToLead(
      key,
      leadId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(assigned
            ? 'Message added to the selected lead.'
            : 'The message or selected lead is no longer available.'),
      ),
    );
    await _load();
  }

  Future<void> _createLeadAndAssign(Map<String, Object?> notification) async {
    final nameController = TextEditingController(
      text: notification['sender']?.toString() ?? '',
    );
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add sender as a lead'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the sender’s number only after you verify it in WhatsApp or your contacts.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Contact name'),
              ),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number with country code',
                ),
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 7 || digits.length > 15) {
                    return 'Enter a valid number (7–15 digits).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Create and link'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();
    if (confirmed != true || !mounted) return;

    try {
      final existing = await DatabaseService.getLeadByPhone(phone);
      final lead = existing ??
          await DatabaseService.getOrCreateLead(
            phoneNumber: phone,
            name: name,
            isUnsaved: true,
            notify: false,
          );
      final key = notification['notification_key']?.toString() ?? '';
      final assigned = await DatabaseService.assignPendingNotificationToLead(
        key,
        lead.id!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(assigned
              ? 'Lead saved and preview linked.'
              : 'Lead saved, but the preview was no longer available.'),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create this lead: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unmatched WhatsApp Previews'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mark_chat_read_outlined,
                            size: 52, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No unmatched previews',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Previews that cannot be matched to one contact stay here until you link them.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pending.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _pending[index];
                    final key = item['notification_key']?.toString() ?? '';
                    final sender =
                        item['sender']?.toString() ?? 'Unknown sender';
                    final message = item['message']?.toString() ?? '';
                    final timestamp = item['timestamp'] as int? ?? 0;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_search_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(sender,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(message),
                            const SizedBox(height: 6),
                            Text(
                              timestamp > 0
                                  ? _dateFormat.format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                          timestamp))
                                  : 'Unknown time',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 12),
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Link to the correct lead',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedLeads[key],
                                  isExpanded: true,
                                  hint: const Text('Choose a lead'),
                                  items: _leads
                                      .map((lead) => DropdownMenuItem<int>(
                                            value: lead.id,
                                            child: Text(
                                              '${lead.displayName} • ${lead.phoneNumber}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: _leads.isEmpty
                                      ? null
                                      : (leadId) => setState(
                                          () => _selectedLeads[key] = leadId),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _selectedLeads[key] == null
                                    ? null
                                    : () => _assign(item),
                                icon: const Icon(Icons.link_rounded),
                                label: const Text('Save under selected lead'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _createLeadAndAssign(item),
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text(
                                    'Create lead from verified number'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
