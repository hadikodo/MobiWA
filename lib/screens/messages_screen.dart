// lib/screens/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';
import 'bulk_message_screen.dart';
import 'pending_notifications_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  static const _messagePageSize = 100;
  late TabController _tabController;
  final ScrollController _messageScrollController = ScrollController();

  // Leads tab state
  List<Lead> _leads = [];
  bool _isLoadingLeads = true;
  String _leadSearch = '';
  String _selectedStatus = 'All';
  bool _onlyUnsaved = false;

  // Messages tab state
  List<LeadMessage> _messages = [];
  bool _isLoadingMessages = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  String _messageSearch = '';
  int _messageOffset = 0;
  int _messageRequestId = 0;

  final List<String> _statuses = [
    'All',
    'New',
    'Contacted',
    'Qualified',
    'Converted',
    'Archived',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _messageScrollController.addListener(_handleMessageScroll);
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _loadLeads();
    _loadRecentMessages();
  }

  void _handleDataChanged() {
    _loadLeads();
    if (_messageSearch.trim().isNotEmpty) {
      _searchMessages(_messageSearch);
    } else {
      _loadRecentMessages();
    }
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging || !mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _messageScrollController
      ..removeListener(_handleMessageScroll)
      ..dispose();
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    super.dispose();
  }

  Future<void> _loadLeads() async {
    setState(() => _isLoadingLeads = true);
    final results = await DatabaseService.getLeads(
      query: _leadSearch.isNotEmpty ? _leadSearch : null,
      status: _selectedStatus != 'All' ? _selectedStatus : null,
      onlyUnsaved: _onlyUnsaved ? true : null,
      limit: 500,
    );
    if (mounted) {
      setState(() {
        _leads = results;
        _isLoadingLeads = false;
      });
    }
  }

  Future<void> _searchMessages(String query) async {
    _messageSearch = query;
    await _loadMessagePage(query: query, reset: true);
  }

  Future<void> _loadRecentMessages() async {
    await _loadMessagePage(query: '', reset: true);
  }

  Future<void> _loadMessagePage({
    required String query,
    required bool reset,
  }) async {
    if (!reset &&
        (_isLoadingMessages || _isLoadingMoreMessages || !_hasMoreMessages)) {
      return;
    }
    final requestId = reset ? ++_messageRequestId : _messageRequestId;
    final pageOffset = reset ? 0 : _messageOffset;
    if (mounted) {
      setState(() {
        if (reset) {
          _isLoadingMessages = true;
          _isLoadingMoreMessages = false;
        } else {
          _isLoadingMoreMessages = true;
        }
      });
    }

    try {
      final results = query.trim().isEmpty
          ? await DatabaseService.getRecentMessages(
              limit: _messagePageSize,
              offset: pageOffset,
            )
          : await DatabaseService.searchMessages(
              query,
              limit: _messagePageSize,
              offset: pageOffset,
            );
      if (!mounted || requestId != _messageRequestId) return;
      setState(() {
        if (reset) {
          _messages = results;
        } else {
          _messages.addAll(results);
        }
        _messageOffset = pageOffset + results.length;
        _hasMoreMessages = results.length == _messagePageSize;
        _isLoadingMessages = false;
        _isLoadingMoreMessages = false;
      });
    } catch (_) {
      if (!mounted || requestId != _messageRequestId) return;
      setState(() {
        _isLoadingMessages = false;
        _isLoadingMoreMessages = false;
      });
    }
  }

  void _handleMessageScroll() {
    if (_messageScrollController.hasClients &&
        _messageScrollController.position.extentAfter < 400) {
      _loadMessagePage(query: _messageSearch, reset: false);
    }
  }

  Future<void> _exportCurrentTab() async {
    final exportedCount = _tabController.index == 0
        ? await ExportService.exportLeadsToCSV(onlyUnsaved: _onlyUnsaved)
        : await ExportService.exportAllMessagesToCSV();
    if (!mounted || exportedCount > 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tabController.index == 0
            ? 'No leads to export.'
            : 'No messages to export.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search & Records'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded), text: 'Leads Directory'),
            Tab(icon: Icon(Icons.search_rounded), text: 'Message Content'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_chat_unread_outlined),
            tooltip: 'Review unmatched WhatsApp previews',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PendingNotificationsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_check_rounded),
            tooltip: 'Draft queue for opted-in contacts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BulkMessageScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: _tabController.index == 0
                ? 'Export leads CSV'
                : 'Export all messages CSV',
            onPressed: _exportCurrentTab,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabController.index == 0) {
                _loadLeads();
              } else if (_messageSearch.trim().isEmpty) {
                _loadRecentMessages();
              } else {
                _searchMessages(_messageSearch);
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Leads Directory
          _buildLeadsTab(),

          // Tab 2: Message Search
          _buildMessagesTab(),
        ],
      ),
    );
  }

  Widget _buildLeadsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SearchBar(
            hintText: 'Search leads by name, phone, notes...',
            leading: const Icon(Icons.search),
            trailing: _leadSearch.isNotEmpty
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _leadSearch = '');
                        _loadLeads();
                      },
                    )
                  ]
                : null,
            onChanged: (val) {
              _leadSearch = val;
              _loadLeads();
            },
          ),
        ),

        // Status & Unsaved filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Unsaved Only'),
                selected: _onlyUnsaved,
                onSelected: (selected) {
                  setState(() => _onlyUnsaved = selected);
                  _loadLeads();
                },
              ),
              const SizedBox(width: 8),
              ..._statuses.map(
                (status) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(status),
                    selected: _selectedStatus == status,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedStatus = status);
                        _loadLeads();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Leads List
        Expanded(
          child: _isLoadingLeads
              ? const Center(child: CircularProgressIndicator())
              : _leads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_search_rounded,
                              size: 54, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No matching leads',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try changing filters or search terms.',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadLeads,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _leads.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final lead = _leads[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: lead.isUnsaved
                                    ? Colors.orange.shade100
                                    : Colors.teal.shade100,
                                child: Icon(
                                  lead.isUnsaved
                                      ? Icons.person_off_rounded
                                      : Icons.person_rounded,
                                  color: lead.isUnsaved
                                      ? Colors.orange.shade800
                                      : Colors.teal.shade800,
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lead.displayName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withAlpha(30),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      lead.status,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (lead.name.isNotEmpty)
                                    Text(lead.phoneNumber,
                                        style: const TextStyle(fontSize: 12)),
                                  if (lead.notes.isNotEmpty)
                                    Text(
                                      lead.notes,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12),
                                    ),
                                ],
                              ),
                              trailing:
                                  const Icon(Icons.chevron_right, size: 20),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DetailScreen(leadId: lead.id!),
                                  ),
                                );
                                _loadLeads();
                              },
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildMessagesTab() {
    final fmt = DateFormat('MMM d, h:mm a');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            hintText: 'Search keyword across all message logs...',
            leading: const Icon(Icons.search),
            trailing: _messageSearch.isNotEmpty
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _messageSearch = '');
                        _searchMessages('');
                      },
                    )
                  ]
                : null,
            onChanged: _searchMessages,
          ),
        ),
        Expanded(
          child: _isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                _messageSearch.isEmpty
                                    ? Icons.chat_bubble_outline
                                    : Icons.find_in_page_outlined,
                                size: 54,
                                color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _messageSearch.isEmpty
                                  ? 'No messages recorded yet'
                                  : 'No matching messages',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _messageSearch.isEmpty
                                  ? 'Incoming WhatsApp previews and messages you confirm as sent will appear here.'
                                  : 'Try another search term.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _messageScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        if (i >= _messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final msg = _messages[i];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              msg.direction == 'outgoing'
                                  ? Icons.call_made_rounded
                                  : Icons.call_received_rounded,
                              color: msg.direction == 'outgoing'
                                  ? Colors.blue
                                  : Colors.green,
                            ),
                            title: Text(msg.message),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (msg.note.isNotEmpty)
                                  Text('Note: ${msg.note}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic)),
                                Text(
                                  '${msg.phoneNumber} • ${fmt.format(msg.dateTime)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 14),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DetailScreen(leadId: msg.leadId),
                                ),
                              );
                              _searchMessages(_messageSearch);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
