// lib/screens/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const _messagePageSize = 100;
  final ScrollController _messageScrollController = ScrollController();

  List<LeadMessage> _messages = [];
  bool _isLoadingMessages = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  String _messageSearch = '';
  int _messageOffset = 0;
  int _messageRequestId = 0;

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleMessageScroll);
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _loadRecentMessages();
  }

  void _handleDataChanged() {
    if (_messageSearch.trim().isNotEmpty) {
      _searchMessages(_messageSearch);
    } else {
      _loadRecentMessages();
    }
  }

  @override
  void dispose() {
    _messageScrollController
      ..removeListener(_handleMessageScroll)
      ..dispose();
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    super.dispose();
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

  Future<void> _exportMessages() async {
    final count = await ExportService.exportAllMessagesToCSV();
    if (!mounted) return;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages to export.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported $count messages to CSV.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF0D9488)),
            SizedBox(width: 8),
            Text('Message History', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export messages CSV',
            onPressed: _exportMessages,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              if (_messageSearch.trim().isEmpty) {
                _loadRecentMessages();
              } else {
                _searchMessages(_messageSearch);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              hintText: 'Search keyword across all customer chats...',
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
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_outlined,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No messages found',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _messageSearch.isNotEmpty
                                  ? 'Try searching a different keyword.'
                                  : 'Messages read by Mobi AI will appear here.',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          if (_messageSearch.trim().isEmpty) {
                            await _loadRecentMessages();
                          } else {
                            await _searchMessages(_messageSearch);
                          }
                        },
                        child: ListView.separated(
                          controller: _messageScrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              _messages.length + (_isLoadingMoreMessages ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            if (i == _messages.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final msg = _messages[i];
                            final isOutgoing = msg.direction == 'outgoing';

                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DetailScreen(leadId: msg.leadId),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                isOutgoing
                                                    ? Icons.call_made_rounded
                                                    : Icons.call_received_rounded,
                                                size: 14,
                                                color: isOutgoing
                                                    ? Colors.teal
                                                    : Colors.blueGrey,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                msg.phoneNumber,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            fmt.format(msg.dateTime),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        msg.message,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (msg.note.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          msg.note,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.indigo.shade600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
