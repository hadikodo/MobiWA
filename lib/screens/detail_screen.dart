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
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _nameController = TextEditingController();
    _notesController = TextEditingController();
    _tagsController = TextEditingController();
    _loadLeadData();
  }

  @override
  void dispose() {
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    _nameController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
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

  Future<void> _analyzeChatWithGemini({bool scrapeLive = false}) async {
    if (_lead == null) return;

    final isConfigured = await GeminiService.isConfigured();
    if (!isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API key is not configured. Add GEMINI_API_KEY to your .env file.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(width: 16),
                Text(scrapeLive
                    ? 'Reading WhatsApp & profiling with Mobi AI...'
                    : 'Mobi AI analyzing customer chat...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      var currentMessages = List<LeadMessage>.from(_messages);

      // Scrape live WhatsApp messages if requested or if current messages list is empty
      if (scrapeLive || currentMessages.isEmpty) {
        final hasA11y = await WhatsAppService.hasAccessibilityAccess();
        if (hasA11y) {
          final scraped = await WhatsAppService.scrapeChatMessages(
            phoneNumber: _lead!.phoneNumber,
          );
          if (scraped.isNotEmpty && _lead!.id != null) {
            await DatabaseService.insertScrapedMessages(
              _lead!.id!,
              _lead!.phoneNumber,
              scraped,
            );
            await _loadLeadData();
            currentMessages =
                await DatabaseService.getMessagesForLead(_lead!.id!);
          }
        }
      }

      if (currentMessages.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No messages found. Enable WhatsApp Accessibility and tap "Read WhatsApp & Profile".',
            ),
          ),
        );
        return;
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
              Icon(Icons.auto_awesome, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Text('Mobi AI Insights'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hub_outlined,
                          size: 16, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Assigned List: ${result.customerList}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3730A3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (result.suggestedName.isNotEmpty) ...[
                  const Text('Detected Name:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(result.suggestedName),
                  const SizedBox(height: 10),
                ],
                const Text('Stage:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(result.status),
                const SizedBox(height: 10),
                const Text('Detected Interest & Requirements:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(result.interestSummary.isNotEmpty
                    ? result.interestSummary
                    : 'General inquiry'),
                const SizedBox(height: 10),
                if (result.nextAction.isNotEmpty) ...[
                  const Text('Recommended Next Action:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    result.nextAction,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (result.lastPurchasedOrRequestedItem.isNotEmpty) ...[
                  const Text('Item Requested / Bought:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(result.lastPurchasedOrRequestedItem),
                  const SizedBox(height: 10),
                ],
                const Text('Categorical Tags:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: result.tags
                      .map((t) => Chip(
                            label: Text('#$t',
                                style: const TextStyle(fontSize: 11)),
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
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5)),
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
            const SnackBar(
              content: Text('Mobi AI profile applied to lead!'),
              backgroundColor: Color(0xFF4F46E5),
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

  Widget _buildAiListBadge(String aiList) {
    Color bg;
    Color fg;
    IconData icon;
    switch (aiList) {
      case 'Hot Leads':
        bg = const Color(0xFFFFE4E6);
        fg = const Color(0xFFBE123C);
        icon = Icons.local_fire_department_rounded;
        break;
      case 'VIP Customers':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        icon = Icons.star_rounded;
        break;
      case 'Warm Inquiries':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF3730A3);
        icon = Icons.chat_bubble_rounded;
        break;
      case 'Converted':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        icon = Icons.verified_rounded;
        break;
      case 'Cold / Follow-Up':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        icon = Icons.ac_unit_rounded;
        break;
      case 'Support':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF5B21B6);
        icon = Icons.support_agent_rounded;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        icon = Icons.label_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            aiList,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobiAiCrmCard() {
    final aiList = _lead!.aiList;
    final hasAi = aiList.isNotEmpty || _lead!.aiSummary.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasAi ? Colors.indigo.shade200 : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      color: hasAi
          ? Colors.indigo.shade50.withAlpha(90)
          : Colors.grey.shade50.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mobi AI • CRM Profile',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Powered by Gemini AI',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Change CRM List',
                  icon: const Icon(Icons.edit_note_rounded, size: 22),
                  onSelected: (selectedList) async {
                    await DatabaseService.setLeadAiList(
                        widget.leadId, selectedList);
                    await _loadLeadData();
                  },
                  itemBuilder: (_) => GeminiService.standardCustomerLists
                      .map(
                        (item) => PopupMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Customer List: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                _buildAiListBadge(aiList.isNotEmpty ? aiList : 'Uncategorized'),
              ],
            ),
            const SizedBox(height: 8),
            if (_lead!.aiSummary.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Need & Interest Summary:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3730A3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lead!.aiSummary,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF1E1B4B)),
                    ),
                    if (_lead!.aiNextAction.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.flag_rounded,
                              size: 13, color: Color(0xFF0F766E)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Next Action: ${_lead!.aiNextAction}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Text(
                'No conversation analyzed yet for this lead.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => _analyzeChatWithGemini(scrapeLive: true),
                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                    label: const Text(
                      'Read WhatsApp & Profile',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                    side: BorderSide(color: Colors.indigo.shade200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: () => _analyzeChatWithGemini(scrapeLive: false),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label:
                      const Text('Re-Analyze', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _openWhatsAppChat() async {
    if (_lead == null) return;
    try {
      await WhatsAppService.openChat(phoneNumber: _lead!.phoneNumber);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp: $e')),
        );
      }
    }
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
            // Mobi AI CRM Profile Card
            _buildMobiAiCrmCard(),
            const SizedBox(height: 16),

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
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _openWhatsAppChat,
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text(
                          'Open WhatsApp Chat',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
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
