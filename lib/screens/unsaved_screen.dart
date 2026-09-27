// lib/screens/unsaved_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';
import '../services/database_service.dart';
import '../services/contact_service.dart';
import '../services/export_service.dart';
import '../services/whatsapp_contact_scanner_service.dart';
import '../services/whatsapp_service.dart';
import '../services/chat_export_number_extractor.dart';
import '../utils/phone_utils.dart';
import 'detail_screen.dart';
import 'bulk_message_screen.dart';
import '../services/gemini_service.dart';

class UnsavedScreen extends StatefulWidget {
  const UnsavedScreen({super.key});

  @override
  State<UnsavedScreen> createState() => _UnsavedScreenState();
}

class _UnsavedScreenState extends State<UnsavedScreen> {
  List<Lead> _unsavedLeads = [];
  bool _isLoading = true;
  bool _isScanning = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    DatabaseService.dataRevision.addListener(_handleDataChanged);
    _loadUnsavedLeads();
  }

  void _handleDataChanged() => _loadUnsavedLeads();

  @override
  void dispose() {
    DatabaseService.dataRevision.removeListener(_handleDataChanged);
    super.dispose();
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

  Future<void> _scanWhatsAppContacts() async {
    // Ensure contacts permission first
    final hasPerm = await ContactService.hasPermission();
    if (!hasPerm) {
      final granted = await ContactService.requestPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacts permission is required to scan.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() => _isScanning = true);

    try {
      final scanned = await WhatsAppContactScannerService.scan(
        onlyUnsaved: true,
      );

      if (!mounted) return;

      if (scanned.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No unsaved WhatsApp contacts found.\n'
              'All WhatsApp numbers are already saved or in your CRM.',
            ),
          ),
        );
        setState(() => _isScanning = false);
        return;
      }

      // Import each scanned number as a lead in the CRM
      int imported = 0;
      for (final contact in scanned) {
        try {
          await DatabaseService.getOrCreateLead(
            phoneNumber: contact.phoneNumber,
            name: contact.displayName,
            isUnsaved: true,
            notify: false,
          );
          imported++;
        } catch (_) {
          // Skip invalid numbers
        }
      }

      if (imported > 0) {
        DatabaseService.notifyDataChanged();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found ${scanned.length} unsaved WhatsApp numbers. '
              '$imported new leads imported to CRM.',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
        _loadUnsavedLeads();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _importHistoricalNumbers() async {
    try {
      final exports = await WhatsAppService.pickMultipleChatExports();
      if (!mounted || exports == null || exports.isEmpty) return;

      // Convert to ChatExportFile list
      final chatFiles = exports
          .map((e) => ChatExportFile(
                fileName: e['name'] ?? '',
                content: e['content'] ?? '',
              ))
          .toList();

      // Extract phone numbers
      final extracted =
          ChatExportNumberExtractor.extractFromExports(chatFiles);

      if (!mounted) return;

      if (extracted.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No phone numbers found in ${chatFiles.length} file(s).\n'
              'Make sure you selected WhatsApp chat export .txt files.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Show confirmation dialog with found numbers
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Found ${extracted.length} Numbers'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From ${chatFiles.length} chat export(s):',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: extracted.length,
                    itemBuilder: (_, i) {
                      final item = extracted[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.phone, size: 18),
                        title: Text(item.phoneNumber),
                        subtitle: Text(item.source,
                            style: const TextStyle(fontSize: 11)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Import All'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      // Import as leads
      int imported = 0;
      for (final item in extracted) {
        try {
          await DatabaseService.getOrCreateLead(
            phoneNumber: item.phoneNumber,
            isUnsaved: true,
            notify: false,
          );
          imported++;
        } catch (_) {}
      }

      if (imported > 0) DatabaseService.notifyDataChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$imported numbers imported to CRM.'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        _loadUnsavedLeads();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Could not open file picker.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _autoScanWhatsAppZeroAction({String? targetPackage, String? appLabel}) async {
    final hasA11y = await WhatsAppService.hasAccessibilityAccess();
    if (!hasA11y) {
      if (!mounted) return;
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.bolt, color: Colors.amber),
              SizedBox(width: 8),
              Text('Enable Automated Scan'),
            ],
          ),
          content: const Text(
            'To automatically collect unsaved numbers without any manual work, '
            'MobiWA uses Android Accessibility to open WhatsApp, scroll through your chats, '
            'and collect all raw unsaved numbers.\n\n'
            'Please enable "MobiWA Auto-Sender" in Accessibility Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (enable == true) {
        await WhatsAppService.openAccessibilitySettings();
      }
      return;
    }

    // If target package not pre-selected, check installed apps and prompt if both exist
    String? selectedPkg = targetPackage;
    String label = appLabel ?? 'WhatsApp';

    if (selectedPkg == null) {
      final installedApps = await WhatsAppService.getInstalledWhatsAppApps();
      if (!mounted) return;

      if (installedApps.length > 1) {
        final chosen = await showDialog<Map<String, String>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.apps, color: Colors.green),
                SizedBox(width: 8),
                Text('Choose WhatsApp App'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select which app to scan for unsaved customer numbers:'),
                const SizedBox(height: 16),
                for (final app in installedApps)
                  ListTile(
                    leading: Icon(
                      app['type'] == 'business'
                          ? Icons.business_center_rounded
                          : Icons.chat_rounded,
                      color: Colors.green.shade700,
                    ),
                    title: Text(
                      app['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(app['packageName'] ?? ''),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    onTap: () => Navigator.pop(ctx, app),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );

        if (chosen == null || !mounted) return;
        selectedPkg = chosen['packageName'];
        label = chosen['name'] ?? 'WhatsApp';
      } else if (installedApps.isNotEmpty) {
        selectedPkg = installedApps.first['packageName'];
        label = installedApps.first['name'] ?? 'WhatsApp';
      }
    }

    setState(() => _isScanning = true);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Auto-scanning $label... Please wait.'),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      final rawNumbers = await WhatsAppService.startAutoScanWhatsApp(
        packageName: selectedPkg,
      );
      if (!mounted) return;

      if (rawNumbers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No unsaved numbers detected in $label.'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      int imported = 0;
      final importedLeadIds = <int>[];
      final timestampStr = DateFormat('MMM d, h:mm a').format(DateTime.now());
      for (final raw in rawNumbers) {
        final clean = PhoneUtils.normalize(raw);
        if (clean.isNotEmpty) {
          try {
            final lead = await DatabaseService.getOrCreateLead(
              phoneNumber: clean,
              isUnsaved: true,
              whatsappOptIn: true,
              tags: 'Scanned, $label',
              notes: 'Imported via $label auto-scan on $timestampStr',
              notify: false,
            );
            if (lead.id != null) {
              importedLeadIds.add(lead.id!);
            }
            imported++;
          } catch (_) {}
        }
      }

      if (imported > 0) DatabaseService.notifyDataChanged();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Auto-Scan Completed'),
              ],
            ),
            content: Text(
              'Successfully scanned $label without manual effort!\n\n'
              '• Captured: ${rawNumbers.length} unsaved numbers\n'
              '• Added to CRM: $imported leads\n\n'
              'Would you like to start auto-messaging these scanned leads now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('View Contacts'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BulkMessageScreen(
                        initialSelectedLeadIds: importedLeadIds,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send Bulk Message'),
              ),
            ],
          ),
        );
        _loadUnsavedLeads();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-scan failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.bolt,
                        color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Get Unsaved Numbers',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.business_center_rounded,
                      color: Colors.green.shade800),
                ),
                title: const Text('⚡ Auto-Scan WhatsApp Business'),
                subtitle: const Text('Zero action: auto-scrolls business chats'),
                onTap: () {
                  Navigator.pop(ctx);
                  _autoScanWhatsAppZeroAction(
                    targetPackage: 'com.whatsapp.w4b',
                    appLabel: 'WhatsApp Business',
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bolt,
                      color: Theme.of(ctx).colorScheme.primary),
                ),
                title: const Text('⚡ Auto-Scan Normal WhatsApp'),
                subtitle: const Text('Zero action: auto-scrolls normal chats'),
                onTap: () {
                  Navigator.pop(ctx);
                  _autoScanWhatsAppZeroAction(
                    targetPackage: 'com.whatsapp',
                    appLabel: 'WhatsApp',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.contactless_rounded),
                title: const Text('Scan WhatsApp Contacts'),
                subtitle: const Text(
                    'Find numbers in Android\'s contact sync'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanWhatsAppContacts();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, color: Colors.indigo.shade700),
                ),
                title: const Text('✨ Mobi AI Profiler & Categorize'),
                subtitle: const Text('Auto-categorize customer interests & items from chat logs'),
                onTap: () {
                  Navigator.pop(ctx);
                  _batchCategorizeWithGemini();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_open_rounded),
                title: const Text('Import from Chat Exports'),
                subtitle: const Text(
                    'Select exported .txt files to extract numbers'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importHistoricalNumbers();
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New messages from unsaved numbers are also captured '
                        'automatically via the notification listener.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearAllUnsavedLeads() async {
    if (_unsavedLeads.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Clear All Unsaved Leads?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove all ${_unsavedLeads.length} unsaved leads from the CRM?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      for (final lead in _unsavedLeads) {
        if (lead.id != null) {
          await DatabaseService.deleteLead(lead.id!);
        }
      }
      DatabaseService.notifyDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All unsaved leads cleared.'),
            duration: Duration(seconds: 2),
          ),
        );
        _loadUnsavedLeads();
      }
    }
  }

  Future<void> _batchCategorizeWithGemini() async {
    if (_unsavedLeads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No leads available to categorize.')),
      );
      return;
    }

    final hasA11y = await WhatsAppService.hasAccessibilityAccess();
    if (!hasA11y && mounted) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.accessibility_new_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Accessibility Required'),
            ],
          ),
          content: const Text(
            'To automatically read chat conversations and allow Mobi AI to extract customer interests and items, '
            'MobiWA needs Android Accessibility enabled.\n\n'
            'Please enable "MobiWA Auto-Sender" in Accessibility Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (enable == true) {
        await WhatsAppService.openAccessibilitySettings();
      }
      return;
    }

    final isConfigured = await GeminiService.isConfigured();
    if (!isConfigured) {
      final configured = await _showGeminiApiKeyDialog();
      if (!configured || !mounted) return;
    }

    setState(() => _isScanning = true);

    int processed = 0;
    int scrapedCount = 0;
    try {
      for (int i = 0; i < _unsavedLeads.length; i++) {
        final lead = _unsavedLeads[i];
        if (lead.id == null) continue;

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('AI Profiling [${i + 1}/${_unsavedLeads.length}]: ${lead.phoneNumber}...'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }

        try {
          var messages = await DatabaseService.getMessagesForLead(lead.id!);

          // If no messages in database yet, automatically scrape the active chat
          if (messages.isEmpty) {
            try {
              final scraped = await WhatsAppService.scrapeChatMessages(
                phoneNumber: lead.phoneNumber,
              );
              if (scraped.isNotEmpty) {
                for (final item in scraped) {
                  final text = item['message'] ?? '';
                  final dir = item['direction'] ?? 'incoming';
                  final ts = int.tryParse(item['timestamp'] ?? '') ??
                      DateTime.now().millisecondsSinceEpoch;
                  if (text.isNotEmpty) {
                    await DatabaseService.insertMessage(
                      LeadMessage(
                        leadId: lead.id!,
                        phoneNumber: lead.phoneNumber,
                        message: text,
                        direction: dir,
                        timestamp: ts,
                        note: 'Live Scraped via WhatsApp Accessibility',
                      ),
                    );
                  }
                }
                scrapedCount++;
                messages = await DatabaseService.getMessagesForLead(lead.id!);
              }
            } catch (_) {}
          }

          final result = await GeminiService.analyzeLeadChat(
            lead: lead,
            messages: messages,
          );
          if (result != null) {
            await GeminiService.applyAnalysisToLead(lead, result);
            processed++;
          }
        } catch (e) {
          debugPrint('Error profiling lead ${lead.phoneNumber}: $e');
        }

        // Brief delay between chat scrapes for smooth UI and API pace
        await Future.delayed(const Duration(milliseconds: 300));
      }

      DatabaseService.notifyDataChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✨ Mobi AI Profiling Complete: Analyzed $processed leads ($scrapedCount chats scraped).'),
            backgroundColor: Colors.indigo.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
        _loadUnsavedLeads();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI profiling failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<bool> _showGeminiApiKeyDialog() async {
    final keyController = TextEditingController();
    final existing = await GeminiService.getApiKey();
    if (!mounted) return false;
    if (existing != null) keyController.text = existing;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Mobi AI Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure your AI engine key to enable smart chat analysis, customer interest profiling, and automatic list categorization.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mobi AI Engine Key',
                hintText: 'Paste API Key...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                await GeminiService.saveApiKey(key);
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Key'),
          ),
        ],
      ),
    );
    return saved ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text('Unsaved Leads (${_unsavedLeads.length})'),
        actions: [
          if (_unsavedLeads.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear All Unsaved Leads',
              onPressed: _clearAllUnsavedLeads,
            ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Unsaved Leads (CSV)',
            onPressed: () async {
              final count =
                  await ExportService.exportLeadsToCSV(onlyUnsaved: true);
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'unsaved_fab',
        onPressed: _isScanning ? null : _showImportOptions,
        icon: _isScanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.person_search_rounded),
        label: Text(_isScanning ? 'Scanning...' : 'Get Numbers'),
        backgroundColor: _isScanning ? Colors.grey : Colors.green.shade700,
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
                                            label: const Text(
                                                'Save to Contacts',
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
