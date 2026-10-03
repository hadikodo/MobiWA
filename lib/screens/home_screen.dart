// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../utils/phone_utils.dart';
import '../services/gemini_service.dart';
import '../services/whatsapp_service.dart';
import '../services/auto_responder_service.dart';
import 'detail_screen.dart';
import 'broadcast_screen.dart';
import 'auto_responder_screen.dart';

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
  };

  Map<String, int> _aiCounts = {};
  List<String> _allAiLists = [];
  bool _autoResponderEnabled = false;
  List<Lead> _recentLeads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _loadDashboardData();
  }

  void _handleDataChanged() => _loadDashboardData();

  @override
  void dispose() {
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final stats = await DatabaseService.getStats();
    final leads = await DatabaseService.getLeads(limit: 10);
    final aiCounts = await DatabaseService.getAiListCounts();
    final allLists = await DatabaseService.getAllAiLists();
    final arSettings = await AutoResponderService.getSettings();
    if (mounted) {
      setState(() {
        _stats = stats;
        _recentLeads = leads;
        _aiCounts = aiCounts;
        _allAiLists = allLists;
        _autoResponderEnabled = arSettings.enabled;
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
                    DropdownMenuItem(
                        value: 'Contacted', child: Text('Contacted')),
                    DropdownMenuItem(
                        value: 'Qualified', child: Text('Qualified')),
                    DropdownMenuItem(
                        value: 'Converted', child: Text('Converted')),
                    DropdownMenuItem(
                        value: 'Archived', child: Text('Archived')),
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
                    hintText:
                        'Customer requested price quotation for wholesale',
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
                      if (!PhoneUtils.looksLikePhoneNumber(phone)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Enter a valid phone number with at least 7 digits.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final isUnsaved = ContactService.isNumberUnsaved(phone);
                      final lead = await DatabaseService.getOrCreateLead(
                        phoneNumber: PhoneUtils.normalize(phone),
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
                    child: const Text('Save Lead Record',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAiListLeadsSheet(String listName) async {
    final leads = await DatabaseService.getLeads(aiList: listName, limit: 100);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$listName (${leads.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  if (leads.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.campaign_rounded, size: 16),
                        label: const Text('Broadcast', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BroadcastScreen(initialList: listName),
                            ),
                          );
                        },
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: leads.isEmpty
                  ? Center(
                      child: Text(
                        'No contacts in "$listName" yet.\nRun Mobi AI Profiler to categorize leads.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: leads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final lead = leads[i];
                        return _LeadCard(
                          lead: lead,
                          onTap: () async {
                            Navigator.pop(ctx);
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runMobiAiCategorizer() async {
    final configured = await GeminiService.isConfigured();
    if (!configured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API key is not configured. Add GEMINI_API_KEY to your .env file.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!mounted) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Mobi AI Customer Profiler'),
          ],
        ),
        content: const Text(
          'Mobi AI analyzes customer chat history, discovers sales interests, determines stage, and assigns each customer into CRM lists (Hot Leads, VIP Customers, Warm Inquiries, Converted, Cold / Follow-Up, Support).\n\nHow would you like to run profiling?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'recorded'),
            child: const Text('Analyze Recorded Chats'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            onPressed: () => Navigator.pop(ctx, 'live'),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Live WhatsApp + AI'),
          ),
        ],
      ),
    );

    if (mode == null || mode == 'cancel' || !mounted) return;

    final candidates = await DatabaseService.getMobiAiCandidates(
      onlyUnanalyzed: false,
      limit: 100,
    );

    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No customer candidates found to categorize.'),
        ),
      );
      return;
    }

    int current = 0;
    int successCount = 0;
    String currentContact = '';
    bool cancelled = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgContext) => StatefulBuilder(
        builder: (dlgContext, setDlgState) {
          Future.microtask(() async {
            for (final lead in candidates) {
              if (cancelled || !mounted) break;
              setDlgState(() {
                current++;
                currentContact = lead.displayName;
              });

              try {
                if (mode == 'live') {
                  final hasA11y = await WhatsAppService.hasAccessibilityAccess();
                  if (hasA11y) {
                    final scraped = await WhatsAppService.scrapeChatMessages(
                      phoneNumber: lead.phoneNumber,
                    );
                    if (scraped.isNotEmpty && lead.id != null) {
                      await DatabaseService.insertScrapedMessages(
                        lead.id!,
                        lead.phoneNumber,
                        scraped,
                      );
                    }
                  }
                }

                if (lead.id != null) {
                  final messages = await DatabaseService.getMessagesForLead(lead.id!);
                  if (messages.isNotEmpty) {
                    final result = await GeminiService.analyzeLeadChat(
                      lead: lead,
                      messages: messages,
                    );
                    if (result != null) {
                      await GeminiService.applyAnalysisToLead(lead, result);
                      successCount++;
                    }
                  }
                }
              } catch (e) {
                debugPrint('Mobi AI Profiler error for ${lead.phoneNumber}: $e');
              }
            }

            if (mounted && dlgContext.mounted) {
              Navigator.pop(dlgContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Mobi AI categorized $successCount customers successfully!',
                  ),
                  backgroundColor: const Color(0xFF4F46E5),
                ),
              );
              _loadDashboardData();
            }
          });

          return AlertDialog(
            title: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Text('Mobi AI Profiling...'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: candidates.isEmpty ? 0 : current / candidates.length,
                ),
                const SizedBox(height: 12),
                Text(
                  'Processing $current of ${candidates.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  currentContact.isNotEmpty ? currentContact : 'Initializing...',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(dlgContext);
                },
                child: const Text('Stop'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCrmListTile(String name, IconData icon, Color fg, Color bg) {
    final count = _aiCounts[name] ?? 0;
    return InkWell(
      onTap: () => _showAiListLeadsSheet(name),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withAlpha(51)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              name,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: fg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getListColor(String name) {
    switch (name) {
      case 'Hot Leads':
        return const Color(0xFFBE123C);
      case 'VIP Customers':
        return const Color(0xFFB45309);
      case 'Warm Inquiries':
        return const Color(0xFF3730A3);
      case 'Converted':
      case 'Customers':
        return const Color(0xFF065F46);
      case 'Cold / Follow-Up':
        return const Color(0xFF475569);
      case 'Support':
        return const Color(0xFF5B21B6);
      default:
        final hash = name.codeUnits.fold(0, (acc, c) => acc + c);
        const palette = [
          Color(0xFF0D9488),
          Color(0xFF2563EB),
          Color(0xFF7C3AED),
          Color(0xFFDB2777),
          Color(0xFFD97706),
          Color(0xFF059669),
          Color(0xFF0891B2),
        ];
        return palette[hash % palette.length];
    }
  }

  IconData _getListIcon(String name) {
    if (name == 'Hot Leads') return Icons.local_fire_department_rounded;
    if (name == 'VIP Customers') return Icons.star_rounded;
    if (name == 'Warm Inquiries') return Icons.chat_bubble_rounded;
    if (name == 'Converted' || name == 'Customers') return Icons.verified_rounded;
    if (name == 'Cold / Follow-Up') return Icons.ac_unit_rounded;
    if (name == 'Support') return Icons.support_agent_rounded;
    final lower = name.toLowerCase();
    if (lower.contains('filter') || lower.contains('oil') || lower.contains('part') || lower.contains('brake')) {
      return Icons.build_circle_outlined;
    }
    return Icons.label_outline_rounded;
  }

  List<Widget> _buildAllCrmListPills() {
    final defaultLists = [
      'Hot Leads',
      'VIP Customers',
      'Warm Inquiries',
      'Converted',
      'Cold / Follow-Up',
      'Support',
    ];

    final Set<String> allSet = {...defaultLists, ..._allAiLists, ..._aiCounts.keys};
    final sortedList = allSet.toList()
      ..sort((a, b) {
        final countA = _aiCounts[a] ?? 0;
        final countB = _aiCounts[b] ?? 0;
        if (countA != countB) return countB.compareTo(countA);
        return a.compareTo(b);
      });

    return sortedList.map((name) {
      final color = _getListColor(name);
      return _buildCrmListTile(
        name,
        _getListIcon(name),
        color,
        color.withAlpha(25),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => const Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mobi AI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Autonomous WhatsApp CRM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
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
        heroTag: 'home_fab',
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
                  label: 'Total Customers',
                  value: '${_stats['totalLeads'] ?? 0}',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF0284C7),
                ),
                _KpiCard(
                  label: 'Unsaved Leads',
                  value: '${_stats['unsavedLeads'] ?? 0}',
                  icon: Icons.person_off_rounded,
                  color: const Color(0xFFEA580C),
                ),
                _KpiCard(
                  label: 'Hot & VIP Leads',
                  value: '${(_aiCounts['Hot Leads'] ?? 0) + (_aiCounts['VIP Customers'] ?? 0)}',
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFFBE123C),
                  onTap: () => _showAiListLeadsSheet('Hot Leads'),
                ),
                _KpiCard(
                  label: 'Chats Recorded',
                  value: '${_stats['totalMessages'] ?? 0}',
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF0D9488),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Quick Actions Banner
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _QuickActionButton(
                      icon: Icons.campaign_rounded,
                      label: 'Broadcast',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BroadcastScreen(),
                          ),
                        );
                        _loadDashboardData();
                      },
                    ),
                    _QuickActionButton(
                      icon: Icons.smart_toy_rounded,
                      label: 'Auto-Reply',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AutoResponderScreen(),
                          ),
                        );
                        _loadDashboardData();
                      },
                    ),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Mobi AI Auto-Responder Live Status Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _autoResponderEnabled
                      ? const Color(0xFF10B981)
                      : Colors.grey.shade300,
                  width: 1.2,
                ),
              ),
              color: _autoResponderEnabled
                  ? const Color(0xFF10B981).withAlpha(18)
                  : Colors.grey.shade50,
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AutoResponderScreen(),
                    ),
                  );
                  _loadDashboardData();
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _autoResponderEnabled
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.smart_toy_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Mobi AI Auto-Responder',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _autoResponderEnabled
                                        ? Colors.green.shade100
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _autoResponderEnabled ? 'ACTIVE' : 'OFF',
                                    style: TextStyle(
                                      color: _autoResponderEnabled
                                          ? Colors.green.shade800
                                          : Colors.grey.shade700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _autoResponderEnabled
                                  ? 'Listening to WhatsApp notifications and replying in your personal style.'
                                  : 'Tap to configure Gemini AI auto-replying.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Mobi AI CRM Hub
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.indigo.shade200, width: 1.2),
              ),
              color: Colors.indigo.shade50.withAlpha(90),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade700,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mobi AI • CRM Lists',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Customer Intelligence & Profiling',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo.shade800,
                                side: BorderSide(color: Colors.indigo.shade300),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const BroadcastScreen(),
                                  ),
                                );
                                _loadDashboardData();
                              },
                              icon: const Icon(Icons.campaign_rounded, size: 14),
                              label: const Text('Broadcast',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.indigo.shade700,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _runMobiAiCategorizer,
                              icon: const Icon(Icons.bolt, size: 14),
                              label: const Text(
                                'Run Profiler',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildAllCrmListPills(),
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
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                      Icon(Icons.inbox_outlined,
                          size: 54, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No leads recorded yet',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Record Lead" to log customer inquiries, unsaved numbers, and messages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
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
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3A52) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF131B2E),
                  const Color(0xFF0F172A),
                ]
              : [
                  Colors.white,
                  color.withValues(alpha: 0.04),
                ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                  ],
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: isDark ? 0.2 : 0.1),
              ),
              child: Icon(icon, color: primary, size: 22),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
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

  Widget _buildAiListBadge(String aiList) {
    if (aiList.isEmpty) return const SizedBox.shrink();
    Color bg;
    Color fg;
    IconData icon;
    switch (aiList) {
      case 'Hot Leads':
        bg = const Color(0xFFFFE4E6);
        fg = const Color(0xFFBE123C);
        icon = Icons.local_fire_department_rounded;
        break;
      case 'VIP Customers':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        icon = Icons.star_rounded;
        break;
      case 'Warm Inquiries':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF3730A3);
        icon = Icons.chat_bubble_rounded;
        break;
      case 'Converted':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        icon = Icons.verified_rounded;
        break;
      case 'Cold / Follow-Up':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        icon = Icons.ac_unit_rounded;
        break;
      case 'Support':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF5B21B6);
        icon = Icons.support_agent_rounded;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        icon = Icons.label_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            aiList,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
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
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: lead.isUnsaved
                                ? const LinearGradient(
                                    colors: [Color(0xFFF97316), Color(0xFFFB923C)],
                                  )
                                : const LinearGradient(
                                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                                  ),
                          ),
                          child: Center(
                            child: Text(
                              lead.displayName.isNotEmpty
                                  ? lead.displayName.substring(0, 1).toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                        if (lead.aiList.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _buildAiListBadge(lead.aiList),
                        ],
                      ],
                    ),
                  ],
                ),
                if (lead.aiSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50.withAlpha(140),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: Colors.indigo.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Mobi AI Insight',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lead.aiSummary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF1E1B4B)),
                        ),
                        if (lead.aiNextAction.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Next: ${lead.aiNextAction}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (lead.lastMessage != null &&
                    lead.lastMessage!.isNotEmpty) ...[
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
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
