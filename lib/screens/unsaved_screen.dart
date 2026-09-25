// lib/screens/unsaved_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';

class UnsavedScreen extends StatefulWidget {
  const UnsavedScreen({super.key});

  @override
  State<UnsavedScreen> createState() => _UnsavedScreenState();
}

class _UnsavedScreenState extends State<UnsavedScreen> {
  List<Lead> _unsavedLeads = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUnsavedLeads();
  }

  Future<void> _loadUnsavedLeads() async {
    setState(() => _isLoading = true);
    final leads = await DatabaseService.getLeads(
      onlyUnsaved: true,
      query: _searchQuery.isNotEmpty ? _searchQuery : null,
      limit: 1000,
    );
    if (mounted) {
      setState(() {
        _unsavedLeads = leads;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSaveToContacts(Lead lead) async {
    final success = await ContactService.saveToDeviceContacts(lead);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${lead.displayName}" to device contacts.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      _loadUnsavedLeads();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save to contacts. Check permissions.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text('Unsaved Leads (${_unsavedLeads.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Unsaved Leads (CSV)',
            onPressed: () async {
              final count = await ExportService.exportLeadsToCSV(onlyUnsaved: true);
              if (!context.mounted) return;
              if (count == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No unsaved leads found.')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadUnsavedLeads,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SearchBar(
              hintText: 'Search unsaved phone, name, notes...',
              leading: const Icon(Icons.search),
              trailing: _searchQuery.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                          _loadUnsavedLeads();
                        },
                      ),
                    ]
                  : null,
              onChanged: (q) {
                _searchQuery = q;
                _loadUnsavedLeads();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _unsavedLeads.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  size: 64, color: Colors.green.shade300),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No matching unsaved leads found'
                                    : 'All leads are saved in contacts!',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try adjusting your search criteria.'
                                    : 'When new leads with unrecognized phone numbers are recorded, they will show up here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadUnsavedLeads,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _unsavedLeads.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final lead = _unsavedLeads[i];
                            return Card(
                              child: InkWell(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DetailScreen(leadId: lead.id!),
                                    ),
                                  );
                                  _loadUnsavedLeads();
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  lead.displayName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                if (lead.name.isNotEmpty)
                                                  Text(
                                                    lead.phoneNumber,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.copy,
                                                size: 18),
                                            tooltip: 'Copy Number',
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                  ClipboardData(
                                                      text: lead.phoneNumber));
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Copied: ${lead.phoneNumber}'),
                                                    duration: const Duration(
                                                        seconds: 2),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      if (lead.notes.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          lead.notes,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Updated ${fmt.format(lead.updatedDateTime)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () =>
                                                _handleSaveToContacts(lead),
                                            icon: const Icon(
                                                Icons.person_add_rounded,
                                                size: 15),
                                            label: const Text('Save to Contacts',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
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
