// lib/screens/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/export_service.dart';
import '../models/lead.dart';
import 'detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Lead> _leads = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _unsavedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.newLeads.listen((_) => _load());
  }

  Future<void> _load() async {
    final leads = _unsavedOnly
        ? await DatabaseService.getUnsavedLeads()
        : await DatabaseService.getAllLeads();
    if (mounted) setState(() { _leads = leads; _loading = false; });
  }

  List<Lead> get _filtered {
    if (_searchQuery.isEmpty) return _leads;
    return _leads.where((l) =>
      l.sender.contains(_searchQuery) ||
      l.message.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages (${_leads.length})'),
        actions: [
          IconButton(
            icon: Icon(_unsavedOnly ? Icons.person_off : Icons.people_outline),
            tooltip: _unsavedOnly ? 'Showing unsaved only' : 'Show all',
            onPressed: () {
              setState(() => _unsavedOnly = !_unsavedOnly);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: ExportService.exportAllToCSV,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchBar(
              hintText: 'Search messages...',
              leading: const Icon(Icons.search),
              onChanged: (q) async {
                setState(() => _searchQuery = q);
                if (q.length >= 2) {
                  final results = await DatabaseService.searchLeads(q);
                  if (mounted) setState(() => _leads = results);
                } else if (q.isEmpty) {
                  _load();
                }
              },
            ),
          ),
          if (_unsavedOnly)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Chip(
                    label: const Text('Unsaved only'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() => _unsavedOnly = false);
                      _load();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No messages yet',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                          ],
                        ))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _LeadTile(lead: _filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LeadTile extends StatelessWidget {
  final Lead lead;
  const _LeadTile({required this.lead});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, h:mm a');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: lead.isUnsaved
            ? Colors.orange.shade100
            : theme.colorScheme.primaryContainer,
        child: Icon(
          lead.isGroup ? Icons.group : Icons.person,
          color: lead.isUnsaved
              ? Colors.orange.shade700
              : theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(lead.sender,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          if (lead.isUnsaved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Unsaved',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      subtitle: Text(lead.message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      trailing: Text(fmt.format(lead.dateTime),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DetailScreen(sender: lead.sender))),
    );
  }
}
