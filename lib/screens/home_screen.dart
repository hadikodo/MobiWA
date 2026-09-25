// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {
    'totalLeads': 0,
    'unsavedLeads': 0,
    'totalMessages': 0,
    'recentActivity': 0,
  };

  List<Lead> _recentLeads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final stats = await DatabaseService.getStats();
    final leads = await DatabaseService.getLeads(limit: 10);
    if (mounted) {
      setState(() {
        _stats = stats;
        _recentLeads = leads;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSyncContacts() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Syncing device contacts...'),
        duration: Duration(seconds: 1),
      ),
    );

    final count = await ContactService.syncContacts();
    if (!mounted) return;

    if (count >= 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Successfully synced $count contacts.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _loadDashboardData();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Contacts permission was not granted.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showAddLeadDialog() {
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    final messageController = TextEditingController();
    String selectedStatus = 'New';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                      'Record New Lead',
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
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    hintText: '+1234567890',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Name (Optional)',
                    hintText: 'John Doe',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Lead Status',
                    prefixIcon: Icon(Icons.flag),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'New', child: Text('New')),
                    DropdownMenuItem(value: 'Contacted', child: Text('Contacted')),
                    DropdownMenuItem(value: 'Qualified', child: Text('Qualified')),
                    DropdownMenuItem(value: 'Converted', child: Text('Converted')),
                    DropdownMenuItem(value: 'Archived', child: Text('Archived')),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedStatus = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Inquiry Notes',
                    hintText: 'Customer requested price quotation for wholesale',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Initial Message Received (Optional)',
                    hintText: 'Hi, I need info about your product',
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final phone = phoneController.text.trim();
                      if (phone.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a phone number'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final isUnsaved = ContactService.isNumberUnsaved(phone);
                      final lead = await DatabaseService.getOrCreateLead(
                        phoneNumber: phone,
                        name: nameController.text.trim(),
                        notes: notesController.text.trim(),
                        status: selectedStatus,
                        isUnsaved: isUnsaved,
                      );

                      final initialMsg = messageController.text.trim();
                      if (initialMsg.isNotEmpty) {
                        await DatabaseService.insertMessage(
                          LeadMessage(
                            leadId: lead.id!,
                            phoneNumber: lead.phoneNumber,
                            message: initialMsg,
                            direction: 'incoming',
                            timestamp: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                      }

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        _loadDashboardData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lead saved: ${lead.displayName}'),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      }
                    },
                    child: const Text('Save Lead Record', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Color(0xFF0D9488)),
            SizedBox(width: 8),
            Text('MobiWA', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Device Contacts',
            onPressed: _handleSyncContacts,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLeadDialog,
        icon: const Icon(Icons.add),
        label: const Text('Record Lead'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // KPI Summary Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _KpiCard(
                  label: 'Total Leads',
                  value: '${_stats['totalLeads'] ?? 0}',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF0284C7),
                ),
                _KpiCard(
                  label: 'Unsaved Numbers',
                  value: '${_stats['unsavedLeads'] ?? 0}',
                  icon: Icons.person_off_rounded,
                  color: const Color(0xFFEA580C),
                ),
                _KpiCard(
                  label: 'Messages Recorded',
                  value: '${_stats['totalMessages'] ?? 0}',
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF0D9488),
                ),
                _KpiCard(
                  label: 'Updated Today',
                  value: '${_stats['recentActivity'] ?? 0}',
                  icon: Icons.access_time_filled_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Quick Actions Banner
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _QuickActionButton(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Add Lead',
                      onTap: _showAddLeadDialog,
                    ),
                    _QuickActionButton(
                      icon: Icons.contacts_rounded,
                      label: 'Sync Contacts',
                      onTap: _handleSyncContacts,
                    ),
                    _QuickActionButton(
                      icon: Icons.file_download_outlined,
                      label: 'Export CSV',
                      onTap: () async {
                        final count = await ExportService.exportLeadsToCSV();
                        if (!context.mounted) return;
                        if (count == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No leads found to export.')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_recentLeads.isNotEmpty)
                  Text(
                    'Showing latest ${_recentLeads.length}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Recent Leads List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_recentLeads.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 54, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No leads recorded yet',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Record Lead" to log customer inquiries, unsaved numbers, and messages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentLeads.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final lead = _recentLeads[i];
                  return _LeadCard(
                    lead: lead,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailScreen(leadId: lead.id!),
                        ),
                      );
                      _loadDashboardData();
                    },
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

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final VoidCallback onTap;

  const _LeadCard({required this.lead, required this.onTap});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'New':
        return Colors.blue;
      case 'Contacted':
        return Colors.teal;
      case 'Qualified':
        return Colors.purple;
      case 'Converted':
        return Colors.green;
      case 'Archived':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(lead.status);
    final fmt = DateFormat('MMM d, h:mm a');

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: lead.isUnsaved
                              ? Colors.orange.shade100
                              : Colors.teal.shade100,
                          child: Icon(
                            lead.isUnsaved
                                ? Icons.person_off_rounded
                                : Icons.person_rounded,
                            size: 18,
                            color: lead.isUnsaved
                                ? Colors.orange.shade800
                                : Colors.teal.shade800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lead.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (lead.name.isNotEmpty)
                                Text(
                                  lead.phoneNumber,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lead.status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (lead.isUnsaved) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Unsaved',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (lead.lastMessage != null && lead.lastMessage!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lead.lastMessage!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (lead.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  lead.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message_outlined,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${lead.messageCount} messages',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Text(
                    fmt.format(lead.updatedDateTime),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
