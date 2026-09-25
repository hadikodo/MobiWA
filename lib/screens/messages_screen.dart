// lib/screens/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Leads tab state
  List<Lead> _leads = [];
  bool _isLoadingLeads = true;
  String _leadSearch = '';
  String _selectedStatus = 'All';
  bool _onlyUnsaved = false;

  // Messages tab state
  List<LeadMessage> _messages = [];
  bool _isLoadingMessages = false;
  String _messageSearch = '';

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
    _loadLeads();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    if (query.trim().isEmpty) {
      setState(() {
        _messages = [];
        _isLoadingMessages = false;
      });
      return;
    }

    setState(() => _isLoadingMessages = true);
    final results = await DatabaseService.searchMessages(query, limit: 100);
    if (mounted) {
      setState(() {
        _messages = results;
        _isLoadingMessages = false;
      });
    }
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
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
            onPressed: () => ExportService.exportLeadsToCSV(
              onlyUnsaved: _onlyUnsaved,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabController.index == 0) {
                _loadLeads();
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
                              trailing: const Icon(Icons.chevron_right, size: 20),
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
              : _messageSearch.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.find_in_page_outlined,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'Search Message Transcripts',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Type keywords above to find specific conversations, customer requests, or message notes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages containing "$_messageSearch"',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _messages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
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
                                trailing: const Icon(Icons.arrow_forward_ios,
                                    size: 14),
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
