// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import '../services/whatsapp_service.dart';
import '../services/gemini_service.dart';

class DetailScreen extends StatefulWidget {
  final int leadId;
  const DetailScreen({super.key, required this.leadId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with WidgetsBindingObserver {
  Lead? _lead;
  List<LeadMessage> _messages = [];
  bool _isLoading = true;

  late TextEditingController _nameController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;
  String _currentStatus = 'New';
  _PendingOutgoingMessage? _pendingOutgoingMessage;
  bool _confirmingReturnedMessage = false;

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
    WidgetsBinding.instance.addObserver(this);
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _nameController = TextEditingController();
    _notesController = TextEditingController();
    _tagsController = TextEditingController();
    _loadLeadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    _nameController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _confirmReturnedOutgoingMessage();
    }
  }

  Future<void> _confirmReturnedOutgoingMessage() async {
    final pending = _pendingOutgoingMessage;
    if (pending == null || _confirmingReturnedMessage || !mounted) return;
    _pendingOutgoingMessage = null;
    _confirmingReturnedMessage = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Did you send this message?'),
        content: const Text(
          'MobiWA cannot verify delivery in WhatsApp. Confirm only if you tapped Send; then the message will be added to this lead’s history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not sent'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, save to history'),
          ),
        ],
      ),
    );
    if (sent == true && mounted) {
      await DatabaseService.insertMessage(
        LeadMessage(
          leadId: widget.leadId,
          phoneNumber: pending.phoneNumber,
          message: pending.message,
          direction: 'outgoing',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          note: 'Sent via WhatsApp (user confirmed)',
        ),
      );
      await _loadLeadData();
    }
    _confirmingReturnedMessage = false;
  }

  void _handleDataChanged() {
    final lead = _lead;
    final preserveEdits = lead != null &&
        (_nameController.text != lead.name ||
            _notesController.text != lead.notes ||
            _tagsController.text != lead.tags ||
            _currentStatus != lead.status);
    _loadLeadData(preserveEdits: preserveEdits);
  }

  Future<void> _loadLeadData({bool preserveEdits = false}) async {
    setState(() => _isLoading = true);
    final lead = await DatabaseService.getLeadById(widget.leadId);
    if (lead != null) {
      final messages = await DatabaseService.getMessagesForLead(widget.leadId);
      if (mounted) {
        setState(() {
          _lead = lead;
          _messages = messages;
          if (!preserveEdits) {
            _nameController.text = lead.name;
            _notesController.text = lead.notes;
            _tagsController.text = lead.tags;
          }
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

  Future<void> _analyzeChatWithGemini() async {
    if (_lead == null) return;

    final isConfigured = await GeminiService.isConfigured();
    if (!isConfigured) {
      final configured = await _showGeminiApiKeyDialog();
      if (!configured || !mounted) return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(width: 16),
                Text('Mobi AI analyzing customer chat...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      var currentMessages = List<LeadMessage>.from(_messages);

      // If no messages recorded in DB, auto-scrape live from WhatsApp
      if (currentMessages.isEmpty) {
        final hasA11y = await WhatsAppService.hasAccessibilityAccess();
        if (hasA11y) {
          final scraped = await WhatsAppService.scrapeChatMessages(
            phoneNumber: _lead!.phoneNumber,
          );
          if (scraped.isNotEmpty) {
            for (final item in scraped) {
              final text = item['message'] ?? '';
              final dir = item['direction'] ?? 'incoming';
              final ts = int.tryParse(item['timestamp'] ?? '') ??
                  DateTime.now().millisecondsSinceEpoch;
              if (text.isNotEmpty) {
                await DatabaseService.insertMessage(
                  LeadMessage(
                    leadId: _lead!.id!,
                    phoneNumber: _lead!.phoneNumber,
                    message: text,
                    direction: dir,
                    timestamp: ts,
                    note: 'Live Scraped via WhatsApp Accessibility',
                  ),
                );
              }
            }
            await _loadLeadData();
            currentMessages = await DatabaseService.getMessagesForLead(_lead!.id!);
          }
        }
      }

      final result = await GeminiService.analyzeLeadChat(
        lead: _lead!,
        messages: currentMessages,
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mobi AI could not analyze this chat.')),
        );
        return;
      }

      // Show confirmation dialog with AI findings
      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Mobi AI Insights'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (result.suggestedName.isNotEmpty) ...[
                  const Text('Detected Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(result.suggestedName),
                  const SizedBox(height: 10),
                ],
                const Text('Stage:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(result.status),
                const SizedBox(height: 10),
                const Text('Detected Interest & Requirements:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(result.interestSummary.isNotEmpty ? result.interestSummary : 'General inquiry'),
                const SizedBox(height: 10),
                if (result.lastPurchasedOrRequestedItem.isNotEmpty) ...[
                  const Text('Item Requested / Bought:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(result.lastPurchasedOrRequestedItem),
                  const SizedBox(height: 10),
                ],
                const Text('Categorical Tags:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: result.tags
                      .map((t) => Chip(
                            label: Text('#$t', style: const TextStyle(fontSize: 11)),
                            backgroundColor: Colors.indigo.shade50,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Discard'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Apply AI Profile'),
            ),
          ],
        ),
      );

      if (apply == true && mounted) {
        await GeminiService.applyAnalysisToLead(_lead!, result);
        await _loadLeadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Mobi AI profile applied to lead!'),
              backgroundColor: Colors.indigo.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI analysis failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<bool> _showGeminiApiKeyDialog() async {
    final keyController = TextEditingController();
    final existing = await GeminiService.getApiKey();
    if (!mounted) return false;
    if (existing != null) keyController.text = existing;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Mobi AI Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure your AI engine key to enable smart chat analysis, customer interest profiling, and list categorization.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mobi AI Engine Key',
                hintText: 'Paste API Key...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                await GeminiService.saveApiKey(key);
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Key'),
          ),
        ],
      ),
    );
    return saved ?? false;
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

  Future<void> _showWhatsAppComposer() async {
    if (_lead == null) return;
    if (!_lead!.whatsappOptIn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Record recipient opt-in first'),
          content: const Text(
            'Only prepare a WhatsApp message after the recipient has agreed to receive messages. Record their consent on this lead first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Record opt-in'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await DatabaseService.setWhatsAppOptIn(widget.leadId, true);
      await _loadLeadData();
      if (!mounted) return;
    }
    final messageController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prepare WhatsApp message',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('To ${_lead!.displayName} • ${_lead!.phoneNumber}'),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message draft',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'WhatsApp will open with this draft. Review it and tap Send in WhatsApp. MobiWA does not send or mark it sent automatically.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open WhatsApp'),
                onPressed: () async {
                  try {
                    final message = messageController.text.trim();
                    if (message.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a message draft first.')),
                      );
                      return;
                    }
                    _pendingOutgoingMessage = _PendingOutgoingMessage(
                      phoneNumber: _lead!.phoneNumber,
                      message: message,
                    );
                    await WhatsAppService.openChat(
                      phoneNumber: _lead!.phoneNumber,
                      message: message,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } on PlatformException catch (error) {
                    _pendingOutgoingMessage = null;
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(
                                error.message ?? 'Could not open WhatsApp.')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
    messageController.dispose();
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
            onPressed: () =>
                ExportService.exportLeadConversation(widget.leadId),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Lead',
            onPressed: _handleDeleteLead,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'detail_fab',
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

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _showWhatsAppComposer,
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('Prepare WhatsApp Message'),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _lead!.whatsappOptIn,
                      title: const Text('Recipient has opted in'),
                      subtitle: const Text(
                        'Enable only after recording their permission to receive WhatsApp messages. Turn off on opt-out.',
                      ),
                      onChanged: (value) async {
                        await DatabaseService.setWhatsAppOptIn(
                          widget.leadId,
                          value,
                        );
                      },
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
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
                        hintText:
                            'Customer requested quotation for 500 units...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo.shade700,
                            side: BorderSide(color: Colors.indigo.shade200),
                          ),
                          onPressed: _analyzeChatWithGemini,
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Mobi AI Analyze'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _saveLeadInfo,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Update Lead Info'),
                        ),
                      ],
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
                                color:
                                    isOutgoing ? Colors.teal : Colors.blueGrey,
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

class _PendingOutgoingMessage {
  const _PendingOutgoingMessage({
    required this.phoneNumber,
    required this.message,
  });

  final String phoneNumber;
  final String message;
}
