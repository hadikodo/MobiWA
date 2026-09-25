// lib/screens/unsaved_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';

class UnsavedScreen extends StatefulWidget {
  const UnsavedScreen({super.key});

  @override
  State<UnsavedScreen> createState() => _UnsavedScreenState();
}

class _UnsavedScreenState extends State<UnsavedScreen> {
  List<Map<String, dynamic>> _senders = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.newLeads.listen((_) => _load());
  }

  Future<void> _load() async {
    final senders = await DatabaseService.getUnsavedSenders();
    if (mounted) {
      setState(() {
        _senders = senders;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _senders;
    return _senders.where((s) =>
      s['sender'].toString().contains(_searchQuery) ||
      s['last_message'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Unsaved Contacts (${_senders.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              await ExportService.exportUnsavedToCSV();
            },
            tooltip: 'Export to CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchBar(
              hintText: 'Search phone or message...',
              leading: const Icon(Icons.search),
              onChanged: (q) => setState(() => _searchQuery = q),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _EmptyState(hasSearch: _searchQuery.isNotEmpty)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final s = _filtered[i];
                            return _UnsavedTile(sender: s, onRefresh: _load);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _UnsavedTile extends StatelessWidget {
  final Map<String, dynamic> sender;
  final VoidCallback onRefresh;

  const _UnsavedTile({required this.sender, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final phone = sender['sender'] as String;
    final count = sender['message_count'] as int;
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(sender['last_seen'] as int);
    final lastMsg = sender['last_message'] as String;
    final fmt = DateFormat('MMM d, h:mm a');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Colors.orange.shade100,
        child: Icon(Icons.person_off, color: Colors.orange.shade700),
      ),
      title: Text(phone, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('$count messages', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(width: 8),
              Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(fmt.format(lastSeen), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'copy') {
            await Clipboard.setData(ClipboardData(text: phone));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $phone'), duration: const Duration(seconds: 2)));
            }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'copy', child: ListTile(
            leading: Icon(Icons.copy), title: Text('Copy Number'))),
        ],
      ),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DetailScreen(sender: phone))),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No results found' : 'No unsaved contacts yet',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 8),
            Text(
              'Unsaved WhatsApp senders will appear here\nautomatically as messages arrive',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
