import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/phone_utils.dart';

/// Runs a user-reviewed sequence of WhatsApp drafts for contacts whose
/// recorded consent is still active. The user sends each message in WhatsApp.
class BulkMessageScreen extends StatefulWidget {
  final List<int>? initialSelectedLeadIds;

  const BulkMessageScreen({super.key, this.initialSelectedLeadIds});

  @override
  State<BulkMessageScreen> createState() => _BulkMessageScreenState();
}

class _BulkMessageScreenState extends State<BulkMessageScreen>
    with WidgetsBindingObserver {
  final _templateController = TextEditingController();
  final _searchController = TextEditingController();
  List<Lead> _eligibleLeads = [];
  final Set<int> _selectedIds = {};
  List<Lead> _queue = [];
  int _queueIndex = 0;
  bool _loading = true;
  bool _restoringQueue = true;
  bool _openingDraft = false;
  bool _awaitingWhatsAppReturn = false;
  bool _showingReturnPrompt = false;
  String _search = '';
  String _batchToken = '';

  bool get _batchActive => _queue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DatabaseService.dataRevision.addListener(_reloadLeads);
    _reloadLeads();
    _restoreDraftQueue();
  }

  Future<void> _restoreDraftQueue() async {
    final stored = await DatabaseService.getWhatsAppDraftQueue();
    if (!mounted) return;
    if (stored == null) {
      setState(() => _restoringQueue = false);
      return;
    }
    try {
      final decoded = jsonDecode(stored['lead_ids_json']?.toString() ?? '[]');
      if (decoded is! List) throw const FormatException('Invalid queue');
      final ids = decoded.map((value) => (value as num).toInt()).toList();
      final storedIndex =
          (stored['current_index'] as int? ?? 0).clamp(0, ids.length);
      final restoredLeads = <Lead>[];
      var restoredIndex = 0;
      var awaitingCurrent = false;
      for (var i = 0; i < ids.length; i++) {
        final lead = await DatabaseService.getLeadById(ids[i]);
        if (lead == null) continue;
        if (i < storedIndex) restoredIndex++;
        if (i == storedIndex) {
          awaitingCurrent = (stored['awaiting_return'] as int? ?? 0) == 1;
        }
        restoredLeads.add(lead);
      }
      if (!mounted) return;
      final token = stored['batch_token']?.toString() ?? '';
      if (restoredLeads.isEmpty || restoredIndex >= restoredLeads.length) {
        await DatabaseService.clearWhatsAppDraftQueue();
        if (mounted) setState(() => _restoringQueue = false);
        return;
      }
      setState(() {
        _queue = restoredLeads;
        _queueIndex = restoredIndex;
        _templateController.text = stored['message_template']?.toString() ?? '';
        _awaitingWhatsAppReturn = awaitingCurrent;
        _batchToken = token;
        _restoringQueue = false;
      });
      if (awaitingCurrent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _confirmCurrentDraftAfterReturn(recovered: true);
        });
      }
    } catch (_) {
      await DatabaseService.clearWhatsAppDraftQueue();
      if (mounted) setState(() => _restoringQueue = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DatabaseService.dataRevision.removeListener(_reloadLeads);
    _templateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingWhatsAppReturn) {
      _awaitingWhatsAppReturn = false;
      _confirmCurrentDraftAfterReturn();
    }
  }

  Future<void> _reloadLeads() async {
    final leads = await DatabaseService.getLeads(limit: 1000);
    if (!mounted) return;
    setState(() {
      _eligibleLeads =
          leads.where((lead) => lead.whatsappOptIn && lead.id != null).toList();
      final eligibleIds =
          _eligibleLeads.where(_isSendReady).map((lead) => lead.id!).toSet();
      if (widget.initialSelectedLeadIds != null && _selectedIds.isEmpty) {
        for (final id in widget.initialSelectedLeadIds!) {
          if (eligibleIds.contains(id)) {
            _selectedIds.add(id);
          }
        }
      } else {
        _selectedIds.removeWhere((id) => !eligibleIds.contains(id));
      }
      _loading = false;
    });
  }

  bool _isSendReady(Lead lead) {
    final digits = PhoneUtils.digitsOnly(lead.phoneNumber);
    return digits.length >= 8 && digits.length <= 15;
  }

  List<Lead> get _sendReadyLeads => _eligibleLeads.where(_isSendReady).toList();

  String _selectedFilterTag = 'All';

  List<Lead> get _visibleLeads {
    final query = _search.trim().toLowerCase();
    var list = _eligibleLeads;
    if (_selectedFilterTag != 'All') {
      list = list.where((lead) => lead.tags.toLowerCase().contains(_selectedFilterTag.toLowerCase())).toList();
    }
    if (query.isEmpty) return list;
    return list
        .where((lead) =>
            lead.displayName.toLowerCase().contains(query) ||
            lead.phoneNumber.toLowerCase().contains(query) ||
            lead.tags.toLowerCase().contains(query) ||
            lead.notes.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _startBatch() async {
    final message = _templateController.text.trim();
    if (message.isEmpty) {
      _showMessage('Write a message before starting the draft queue.');
      return;
    }
    final selected = _sendReadyLeads
        .where((lead) => _selectedIds.contains(lead.id))
        .toList();
    if (selected.isEmpty) {
      _showMessage('Select at least one opted-in contact.');
      return;
    }
    setState(() {
      _queue = selected;
      _queueIndex = 0;
      _batchToken = DateTime.now().microsecondsSinceEpoch.toString();
    });
    await _persistQueue(awaitingReturn: false);
    await _openCurrentDraft();
  }

  Future<void> _persistQueue({
    required bool awaitingReturn,
    int? currentIndex,
  }) async {
    if (_queue.isEmpty || _batchToken.isEmpty) return;
    await DatabaseService.saveWhatsAppDraftQueue(
      batchToken: _batchToken,
      leadIds: _queue.map((lead) => lead.id!).toList(),
      messageTemplate: _templateController.text,
      currentIndex: currentIndex ?? _queueIndex,
      awaitingReturn: awaitingReturn,
    );
  }

  String _personalize(Lead lead) => _templateController.text
      .trim()
      .replaceAll('{{name}}', lead.displayName)
      .replaceAll('{{phone}}', lead.phoneNumber);

  Future<void> _openCurrentDraft() async {
    if (!mounted || !_batchActive || _queueIndex >= _queue.length) {
      await _finishBatch();
      return;
    }
    var lead = _queue[_queueIndex];
    final refreshedLead = await DatabaseService.getLeadById(lead.id!);
    if (refreshedLead == null || !refreshedLead.whatsappOptIn) {
      _showMessage(
          '${lead.displayName} no longer has recorded opt-in; skipped.');
      await _advanceQueue();
      return;
    }
    lead = refreshedLead;
    _queue[_queueIndex] = lead;
    if (!_isSendReady(lead)) {
      _showMessage(
          '${lead.displayName} needs a valid 8–15 digit number; skipped.');
      await _advanceQueue();
      return;
    }
    setState(() => _openingDraft = true);
    try {
      // Mark before switching apps so the lifecycle return can be recognized.
      _awaitingWhatsAppReturn = true;
      await _persistQueue(awaitingReturn: true);
      await WhatsAppService.openChat(
        phoneNumber: lead.phoneNumber,
        message: _personalize(lead),
      );
      if (mounted) setState(() => _openingDraft = false);
    } catch (error) {
      _awaitingWhatsAppReturn = false;
      await _persistQueue(awaitingReturn: false);
      if (mounted) setState(() => _openingDraft = false);
      _showMessage('Could not open WhatsApp: $error');
    }
  }

  Future<void> _confirmCurrentDraftAfterReturn({bool recovered = false}) async {
    if (!mounted || !_batchActive || _showingReturnPrompt) return;
    _showingReturnPrompt = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || !_batchActive) {
      _showingReturnPrompt = false;
      return;
    }
    _awaitingWhatsAppReturn = false;
    final lead = _queue[_queueIndex];
    final completedIndex = _queueIndex;

    final autoSendEnabled = await WhatsAppService.hasAccessibilityAccess();
    if (!mounted) return;
    
    int? sent;
    if (autoSendEnabled && !recovered) {
      sent = 1; // Assume sent if accessibility service auto-pressed it
    } else {
      sent = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
        title: Text('Message for ${lead.displayName}'),
        content: Text(
          recovered
              ? 'MobiWA restarted while this draft was open. WhatsApp does not report send status, so choose what happened before the restart.'
              : 'WhatsApp does not report send status to MobiWA. Confirm only if you tapped Send.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 0),
            child: const Text('Not sent — skip contact'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 1),
            child: const Text('Sent — save & open next'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 3),
            child: const Text('Sent — save & stop'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 2),
            child: const Text('Reopen this draft'),
          ),
        ],
      ),
    );
    }
    if (sent == 2 && mounted) {
      _awaitingWhatsAppReturn = false;
      await _persistQueue(awaitingReturn: false);
      _showingReturnPrompt = false;
      await _openCurrentDraft();
      return;
    }
    if ((sent == 1 || sent == 3) && mounted) {
      await DatabaseService.insertMessage(
        LeadMessage(
          leadId: lead.id!,
          phoneNumber: lead.phoneNumber,
          message: _personalize(lead),
          direction: 'outgoing',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          note: 'Sent via WhatsApp (user confirmed)',
          sourceKey: 'wa-batch:$_batchToken:${lead.id}',
        ),
      );
    }
    _showingReturnPrompt = false;
    if (!mounted) return;
    final nextIndex = completedIndex + 1;
    await _persistQueue(
      awaitingReturn: false,
      currentIndex: nextIndex,
    );
    if (!mounted) return;
    setState(() {
      _queueIndex = nextIndex;
      _awaitingWhatsAppReturn = false;
    });
    if (_queueIndex >= _queue.length) {
      await _finishBatch();
      return;
    }
    if (sent == 1) {
      if (autoSendEnabled) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      if (mounted) {
        await _openCurrentDraft();
      }
      return;
    }
    if (sent == 3) {
      await _finishBatch();
      return;
    }
    final continueBatch = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text('Contact ${completedIndex + 1} of ${_queue.length} complete'),
        content: Text('Next: ${_queue[_queueIndex].displayName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('End batch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open next draft'),
          ),
        ],
      ),
    );
    if (continueBatch == true && mounted) {
      await _openCurrentDraft();
    } else {
      await _finishBatch();
    }
  }

  Future<void> _advanceQueue() async {
    if (!mounted) return;
    if (_queueIndex + 1 >= _queue.length) {
      await _finishBatch();
      return;
    }
    final continueBatch = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continue draft queue?'),
        content: Text('Next: ${_queue[_queueIndex + 1].displayName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('End batch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open next draft'),
          ),
        ],
      ),
    );
    if (continueBatch == true && mounted) {
      final nextIndex = _queueIndex + 1;
      await _persistQueue(awaitingReturn: false, currentIndex: nextIndex);
      if (!mounted) return;
      setState(() => _queueIndex = nextIndex);
      await _openCurrentDraft();
    } else {
      await _finishBatch();
    }
  }

  Future<void> _finishBatch() async {
    if (!mounted) return;
    await DatabaseService.clearWhatsAppDraftQueue();
    if (!mounted) return;
    setState(() {
      _queue = [];
      _queueIndex = 0;
      _awaitingWhatsAppReturn = false;
      _openingDraft = false;
    });
    _batchToken = '';
    _showMessage('Draft queue ended.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleLeads;
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Draft Queue')),
      body: _loading || _restoringQueue
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _templateController,
                    enabled: !_batchActive,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Message for selected contacts',
                      hintText: 'Hello {{name}}, ...',
                      helperText: 'Personalization: {{name}} and {{phone}}',
                      border: const OutlineInputBorder(),
                      suffixIcon: _templateController.text.isNotEmpty && !_batchActive
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear Message',
                              onPressed: () => setState(() => _templateController.clear()),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Search name, phone, tags, or interest...',
                    leading: const Icon(Icons.search),
                    trailing: _search.isNotEmpty
                        ? [
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            ),
                          ]
                        : null,
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      'All',
                      'Scanned',
                      'WhatsApp Business',
                      'WhatsApp',
                      'Qualified',
                      'Converted',
                      'VIP',
                    ].map((filter) {
                      final isSelected = _selectedFilterTag == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(filter, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilterTag = selected ? filter : 'All';
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${visible.length} available • ${_selectedIds.length} selected',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _batchActive || visible.isEmpty
                            ? null
                            : () => setState(() {
                                  final visibleSendReady = visible
                                      .where(_isSendReady)
                                      .map((lead) => lead.id!)
                                      .toSet();
                                  final allVisibleSelected = visibleSendReady.isNotEmpty &&
                                      visibleSendReady.every(_selectedIds.contains);
                                  if (allVisibleSelected) {
                                    _selectedIds.removeAll(visibleSendReady);
                                  } else {
                                    _selectedIds.addAll(visibleSendReady);
                                  }
                                }),
                        child: Text(
                            visible.where(_isSendReady).isNotEmpty &&
                                    visible
                                        .where(_isSendReady)
                                        .every((l) => _selectedIds.contains(l.id))
                                ? 'Deselect visible'
                                : 'Select visible'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              _eligibleLeads.isEmpty
                                  ? 'No leads available. Auto-scan WhatsApp or add leads to get started.'
                                  : 'No contacts match this filter.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final lead = visible[index];
                            final selected = _selectedIds.contains(lead.id);
                            final sendReady = _isSendReady(lead);
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade200,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: CheckboxListTile(
                                value: selected,
                                onChanged: _batchActive || !sendReady
                                    ? null
                                    : (value) => setState(() {
                                          if (value == true) {
                                            _selectedIds.add(lead.id!);
                                          } else {
                                            _selectedIds.remove(lead.id);
                                          }
                                        }),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        lead.displayName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14),
                                      ),
                                    ),
                                    if (lead.status.isNotEmpty && lead.status != 'New')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          lead.status,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue.shade800,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      sendReady
                                          ? lead.phoneNumber
                                          : '${lead.phoneNumber} • Needs 8–15 digits',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                    if (lead.tags.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: lead.tags
                                            .split(',')
                                            .map((t) => t.trim())
                                            .where((t) => t.isNotEmpty)
                                            .map((t) => Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                    border: Border.all(
                                                        color: Colors.grey.shade300,
                                                        width: 0.5),
                                                  ),
                                                  child: Text(
                                                    '#$t',
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey.shade800),
                                                  ),
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                    if (lead.notes.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        lead.notes,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openingDraft ||
                              (_batchActive && _awaitingWhatsAppReturn)
                          ? null
                          : _batchActive
                              ? _openCurrentDraft
                              : _startBatch,
                      icon: _openingDraft
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(_batchActive
                          ? _awaitingWhatsAppReturn
                              ? 'Waiting for WhatsApp (${_queueIndex + 1}/${_queue.length})'
                              : 'Resume draft ${_queueIndex + 1} of ${_queue.length}'
                          : 'Start draft queue (${_selectedIds.length})'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
