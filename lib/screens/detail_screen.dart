// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';

class DetailScreen extends StatefulWidget {
  final int leadId;
  const DetailScreen({super.key, required this.leadId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Lead? _lead;
  List<LeadMessage> _messages = [];
  bool _isLoading = true;

  late TextEditingController _nameController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;
  String _currentStatus = 'New';

  final List<String> _statuses = [
    'New',
    'Contacted',
    'Qualified',
    'Converted',
    'Archived',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _notesController = TextEditingController();
    _tagsController = TextEditingController();
    _loadLeadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadLeadData() async {
    setState(() => _isLoading = true);
    final lead = await DatabaseService.getLeadById(widget.leadId);
    if (lead != null) {
      final messages = await DatabaseService.getMessagesForLead(widget.leadId);
      if (mounted) {
        setState(() {
          _lead = lead;
          _messages = messages;
          _nameController.text = lead.name;
          _notesController.text = lead.notes;
          _tagsController.text = lead.tags;
          _currentStatus = lead.status;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLeadInfo() async {
    if (_lead == null) return;
    final updated = _lead!.copyWith(
      name: _nameController.text.trim(),
      notes: _notesController.text.trim(),
      tags: _tagsController.text.trim(),
      status: _currentStatus,
    );
    await DatabaseService.updateLead(updated);
    _loadLeadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lead details saved.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _handleSaveToContacts() async {
    if (_lead == null) return;
    final success = await ContactService.saveToDeviceContacts(_lead!);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${_lead!.displayName}" to phone contacts.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      _loadLeadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save contact. Check device permissions.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showAddMessageDialog() {
    final msgController = TextEditingController();
    final noteController = TextEditingController();
    String direction = 'incoming';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Log Message / Inquiry',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'incoming',
                      label: Text('Customer (Incoming)'),
                      icon: Icon(Icons.call_received_rounded),
                    ),
                    ButtonSegment(
                      value: 'outgoing',
                      label: Text('You (Outgoing)'),
                      icon: Icon(Icons.call_made_rounded),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: (set) {
                    setSheetState(() => direction = set.first);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: msgController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message Body *',
                    hintText: 'Type or paste the message content here...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Internal Note (Optional)',
                    hintText: 'e.g. Quotation sent via WhatsApp',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final text = msgController.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter message text.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      await DatabaseService.insertMessage(
                        LeadMessage(
                          leadId: widget.leadId,
                          phoneNumber: _lead!.phoneNumber,
                          message: text,
                          direction: direction,
                          timestamp: DateTime.now().millisecondsSinceEpoch,
                          note: noteController.text.trim(),
                        ),
                      );

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        _loadLeadData();
                      }
                    },
                    child: const Text('Add to Timeline'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeleteLead() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Lead?'),
        content: const Text(
          'This will permanently delete this lead and all logged messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.deleteLead(widget.leadId);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_lead == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lead Not Found')),
        body: const Center(child: Text('This lead record no longer exists.')),
      );
    }

    final fmt = DateFormat('MMM d, yyyy h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(_lead!.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export Transcript (CSV)',
            onPressed: () => ExportService.exportLeadConversation(widget.leadId),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Lead',
            onPressed: _handleDeleteLead,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMessageDialog,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Log Message'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lead Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phone Number & Copy
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _lead!.isUnsaved
                              ? Colors.orange.shade100
                              : Colors.teal.shade100,
                          child: Icon(
                            _lead!.isUnsaved
                                ? Icons.person_off_rounded
                                : Icons.person_rounded,
                            color: _lead!.isUnsaved
                                ? Colors.orange.shade800
                                : Colors.teal.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lead!.phoneNumber,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Created ${fmt.format(_lead!.createdDateTime)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          tooltip: 'Copy Phone',
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: _lead!.phoneNumber));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Copied: ${_lead!.phoneNumber}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),

                    // Unsaved Warning & Action
                    if (_lead!.isUnsaved) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange.shade800, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Not saved in device contacts',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _handleSaveToContacts,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Save Contact',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Editable Fields
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Contact / Business Name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _currentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Lead Stage',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: _statuses
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _currentStatus = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags (e.g. VIP, Wholesale, Lead)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Inquiry Notes & Requirements',
                        hintText: 'Customer requested quotation for 500 units...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _saveLeadInfo,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Update Lead Info'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Messages & Inquiry Timeline Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Message & Inquiry History (${_messages.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton.icon(
                  onPressed: _showAddMessageDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Log Message'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_messages.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.mark_chat_read_outlined,
                            size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'No messages recorded yet',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Log Message" to manually transcribe or record inquiries.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) {
                  final msg = _messages[i];
                  final isOutgoing = msg.direction == 'outgoing';

                  return Align(
                    alignment: isOutgoing
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isOutgoing
                            ? const Color(0xFF0D9488).withAlpha(30)
                            : Colors.grey.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOutgoing
                              ? const Color(0xFF0D9488).withAlpha(80)
                              : Colors.grey.withAlpha(50),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOutgoing
                                    ? Icons.call_made_rounded
                                    : Icons.call_received_rounded,
                                size: 13,
                                color: isOutgoing ? Colors.teal : Colors.blueGrey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOutgoing ? 'Outgoing' : 'Incoming',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOutgoing
                                      ? Colors.teal.shade800
                                      : Colors.blueGrey.shade800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                fmt.format(msg.dateTime),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () async {
                                  await DatabaseService.deleteMessage(msg.id!);
                                  _loadLeadData();
                                },
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            msg.message,
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (msg.note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Note: ${msg.note}',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
