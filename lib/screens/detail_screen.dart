// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/lead.dart';

class DetailScreen extends StatefulWidget {
  final String sender;
  const DetailScreen({super.key, required this.sender});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  List<Lead> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msgs = await DatabaseService.getLeadsBySender(widget.sender);
    if (mounted) setState(() { _messages = msgs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isUnsaved = _messages.isNotEmpty && _messages.first.isUnsaved;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sender, style: const TextStyle(fontSize: 16)),
            if (isUnsaved)
              const Text('Unsaved contact',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy phone number',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.sender));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied: ${widget.sender}'),
                      duration: const Duration(seconds: 2)));
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('No messages'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _MessageBubble(lead: _messages[i]),
                ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Lead lead;
  const _MessageBubble({required this.lead});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, yyyy h:mm a');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.message, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 10, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(fmt.format(lead.dateTime),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      const SizedBox(width: 8),
                      Icon(
                        lead.source == 'backup' ? Icons.history : Icons.notifications,
                        size: 10,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 2),
                      Text(lead.source,
                          style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
