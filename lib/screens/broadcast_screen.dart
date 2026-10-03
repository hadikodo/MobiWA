// lib/screens/broadcast_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/whatsapp_service.dart';

class BroadcastScreen extends StatefulWidget {
  final String? initialList;

  const BroadcastScreen({super.key, this.initialList});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _availableLists = [];
  Map<String, int> _listCounts = {};
  String _selectedList = '';
  List<Lead> _recipients = [];
  Set<int> _selectedRecipientIds = {};
  bool _isLoading = false;

  // Media attachment state
  String? _attachedFilePath;
  String _mediaType = 'none'; // 'none', 'image', 'video', 'audio'

  // Sequential sending state
  int _sequentialIndex = 0;
  bool _isSequentialMode = false;

  @override
  void initState() {
    super.initState();
    _messageController.text =
        'Hello {name}! We have an exclusive update regarding your {item}. Let us know if you need any assistance!';
    _loadLists();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() => _isLoading = true);
    final counts = await DatabaseService.getAiListCounts();
    final allLists = counts.keys.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    String target = widget.initialList ?? '';
    if (target.isEmpty || !counts.containsKey(target)) {
      target = allLists.isNotEmpty ? allLists.first : 'All Leads';
    }

    if (!mounted) return;
    setState(() {
      _listCounts = counts;
      _availableLists = allLists;
      _selectedList = target;
      _isLoading = false;
    });

    await _loadRecipientsForList(target);
  }

  Future<void> _loadRecipientsForList(String listName) async {
    setState(() => _isLoading = true);
    List<Lead> leads;
    if (listName == 'All Leads' || listName.isEmpty) {
      leads = await DatabaseService.getLeads(limit: 500);
    } else {
      leads = await DatabaseService.getLeads(aiList: listName, limit: 500);
    }

    if (!mounted) return;
    setState(() {
      _recipients = leads;
      _selectedRecipientIds = leads.map((l) => l.id!).whereType<int>().toSet();
      _isLoading = false;
      _sequentialIndex = 0;
      _isSequentialMode = false;
    });
  }

  String _formatMessageForLead(Lead lead) {
    var text = _messageController.text;
    final name = lead.name.trim().isNotEmpty ? lead.name.trim() : 'there';
    final item = lead.tags.isNotEmpty
        ? lead.tags.split(',').first.trim()
        : 'recent inquiry';

    text = text.replaceAll('{name}', name);
    text = text.replaceAll('{phone}', lead.phoneNumber);
    text = text.replaceAll('{item}', item);
    return text;
  }

  Future<void> _pickAttachment(String type) async {
    String mime;
    switch (type) {
      case 'image':
        mime = 'image/*';
        break;
      case 'video':
        mime = 'video/*';
        break;
      case 'audio':
        mime = 'audio/*';
        break;
      default:
        mime = '*/*';
    }

    final path = await WhatsAppService.pickMediaFile(type: mime);
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      setState(() {
        _attachedFilePath = path;
        _mediaType = type;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attached ${type.toUpperCase()} successfully.'),
          backgroundColor: const Color(0xFF4F46E5),
        ),
      );
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachedFilePath = null;
      _mediaType = 'none';
    });
  }

  Future<void> _sendBroadcastShare() async {
    final selectedLeads =
        _recipients.where((l) => _selectedRecipientIds.contains(l.id)).toList();
    if (selectedLeads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one recipient.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final sampleText = _formatMessageForLead(selectedLeads.first);

    if (_attachedFilePath != null && _attachedFilePath!.isNotEmpty) {
      final file = File(_attachedFilePath!);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(_attachedFilePath!)],
          text: sampleText,
          subject: 'Broadcast: $_selectedList',
        );
      } else {
        await Share.share(sampleText, subject: 'Broadcast: $_selectedList');
      }
    } else {
      await Share.share(sampleText, subject: 'Broadcast: $_selectedList');
    }

    // Log messages in CRM for all selected recipients
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final lead in selectedLeads) {
      if (lead.id != null) {
        final personalized = _formatMessageForLead(lead);
        await DatabaseService.insertMessage(
          LeadMessage(
            leadId: lead.id!,
            phoneNumber: lead.phoneNumber,
            message: personalized,
            direction: 'outgoing',
            timestamp: now,
            note: 'Broadcast: $_selectedList',
          ),
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Broadcast dispatched to WhatsApp! Logged for ${selectedLeads.length} customers.',
        ),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  void _startSequentialSend() {
    final selectedLeads =
        _recipients.where((l) => _selectedRecipientIds.contains(l.id)).toList();
    if (selectedLeads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one recipient.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSequentialMode = true;
      _sequentialIndex = 0;
    });

    _sendCurrentSequentialLead();
  }

  Future<void> _sendCurrentSequentialLead() async {
    final selectedLeads =
        _recipients.where((l) => _selectedRecipientIds.contains(l.id)).toList();
    if (_sequentialIndex >= selectedLeads.length) {
      setState(() => _isSequentialMode = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All list messages sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    final lead = selectedLeads[_sequentialIndex];
    final personalized = _formatMessageForLead(lead);

    if (_attachedFilePath != null && _attachedFilePath!.isNotEmpty) {
      final file = File(_attachedFilePath!);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(_attachedFilePath!)],
          text: personalized,
        );
      } else {
        await WhatsAppService.openChat(
          phoneNumber: lead.phoneNumber,
          message: personalized,
        );
      }
    } else {
      await WhatsAppService.openChat(
        phoneNumber: lead.phoneNumber,
        message: personalized,
      );
    }

    // Log message
    if (lead.id != null) {
      await DatabaseService.insertMessage(
        LeadMessage(
          leadId: lead.id!,
          phoneNumber: lead.phoneNumber,
          message: personalized,
          direction: 'outgoing',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          note: 'Direct Broadcast: $_selectedList',
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _sequentialIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selectedRecipientIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('List Broadcast & Campaigns'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // List Selector Header
                  Card(
                    elevation: 0,
                    color: const Color(0xFF4F46E5).withAlpha(15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: const Color(0xFF4F46E5).withAlpha(50),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.campaign_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Target Customer List',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4F46E5),
                                      ),
                                    ),
                                    Text(
                                      'AI-segmented list ready for broadcasts',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // List Chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final listName in _availableLists)
                                ChoiceChip(
                                  label: Text(
                                    '$listName (${_listCounts[listName] ?? 0})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _selectedList == listName
                                          ? Colors.white
                                          : Colors.grey.shade800,
                                    ),
                                  ),
                                  selected: _selectedList == listName,
                                  selectedColor: const Color(0xFF4F46E5),
                                  backgroundColor: Colors.white,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() => _selectedList = listName);
                                      _loadRecipientsForList(listName);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Sequential Sending In-Progress Banner
                  if (_isSequentialMode) ...[
                    Card(
                      color: Colors.amber.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.amber.shade400),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sending [$_sequentialIndex / $selectedCount]',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _isSequentialMode = false),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                            LinearProgressIndicator(
                              value: selectedCount > 0
                                  ? _sequentialIndex / selectedCount
                                  : 0,
                              color: const Color(0xFF4F46E5),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _sendCurrentSequentialLead,
                              icon: const Icon(Icons.arrow_forward),
                              label: Text(
                                _sequentialIndex < selectedCount
                                    ? 'Next: ${_recipients[_sequentialIndex].displayName}'
                                    : 'Finished',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Recipients Expansion Tile
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: ExpansionTile(
                      leading: const Icon(Icons.group_outlined,
                          color: Color(0xFF4F46E5)),
                      title: Text(
                        'Recipients ($selectedCount / ${_recipients.length} Selected)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        'Tap to inspect or filter contacts in "$_selectedList"',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedRecipientIds = _recipients
                                        .map((l) => l.id!)
                                        .whereType<int>()
                                        .toSet();
                                  });
                                },
                                child: const Text('Select All'),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedRecipientIds.clear();
                                  });
                                },
                                child: const Text('Deselect All'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _recipients.length,
                          itemBuilder: (ctx, i) {
                            final lead = _recipients[i];
                            final isSelected =
                                _selectedRecipientIds.contains(lead.id);
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(
                                lead.displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                '${lead.phoneNumber} • ${lead.tags.isNotEmpty ? lead.tags : 'No tags'}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true && lead.id != null) {
                                    _selectedRecipientIds.add(lead.id!);
                                  } else if (lead.id != null) {
                                    _selectedRecipientIds.remove(lead.id!);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Message Composer Section
                  Text(
                    'Compose Broadcast Message',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Token Insertion Chips
                  Wrap(
                    spacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: const Text('{name}'),
                        onPressed: () {
                          _messageController.text += ' {name}';
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: const Text('{item}'),
                        onPressed: () {
                          _messageController.text += ' {item}';
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: const Text('{phone}'),
                        onPressed: () {
                          _messageController.text += ' {phone}';
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _messageController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          'Write your broadcast message or caption here...\nUse {name} and {item} for smart personalization.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Media Attachment Section
                  Text(
                    'Media Attachment (Optional)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_attachedFilePath == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAttachment('image'),
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('Image / Photo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAttachment('video'),
                            icon: const Icon(Icons.videocam_outlined, size: 18),
                            label: const Text('Video'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAttachment('audio'),
                            icon: const Icon(Icons.mic_none_outlined, size: 18),
                            label: const Text('Voice / Audio'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              _mediaType == 'image'
                                  ? Icons.image
                                  : (_mediaType == 'video'
                                      ? Icons.videocam
                                      : Icons.audiotrack),
                              color: const Color(0xFF4F46E5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Attached ${_mediaType.toUpperCase()} file',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  Text(
                                    _attachedFilePath!.split(Platform.pathSeparator).last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _removeAttachment,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Dispatch Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _sendBroadcastShare,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.share_rounded),
                          label: Text(
                            'Share Broadcast ($selectedCount)',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _startSequentialSend,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text(
                            '1-by-1 Direct Send',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
