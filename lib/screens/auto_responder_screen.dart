// lib/screens/auto_responder_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auto_responder_service.dart';
import '../services/whatsapp_service.dart';
import '../services/database_service.dart';

class AutoResponderScreen extends StatefulWidget {
  const AutoResponderScreen({super.key});

  @override
  State<AutoResponderScreen> createState() => _AutoResponderScreenState();
}

class _AutoResponderScreenState extends State<AutoResponderScreen>
    with WidgetsBindingObserver {
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _testMessageController = TextEditingController();
  final TextEditingController _whitelistController = TextEditingController();
  final TextEditingController _excludedController = TextEditingController();

  bool _isEnabled = false;
  String _selectedTone = 'Match My Style';
  bool _learnFromHistory = true;
  int _delaySeconds = 2;
  String _targetApp = 'both'; // 'both', 'com.whatsapp', 'com.whatsapp.w4b'
  String _respondMode = 'all'; // 'all', 'unsaved_only', 'saved_only', 'specific_list', 'specific_numbers'
  String _targetAiList = 'Hot Leads';
  List<String> _availableAiLists = [];
  bool _ignoreGroups = true;
  bool _hasNotificationAccess = false;
  bool _isNotificationListenerRunning = false;
  bool _isLoading = true;
  bool _isSaving = false;

  // Simulator state
  String? _simulatedReply;
  bool _isSimulating = false;

  final List<String> _tones = [
    'Match My Style',
    'Professional & Courteous',
    'Warm & Friendly',
    'Short & Direct',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _testMessageController.text =
        'Hello! Do you have oil filters for Toyota in stock? How much is it?';
    AutoResponderService.logRevision.addListener(_onLogsUpdated);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AutoResponderService.logRevision.removeListener(_onLogsUpdated);
    _instructionsController.dispose();
    _testMessageController.dispose();
    _whitelistController.dispose();
    _excludedController.dispose();
    super.dispose();
  }

  void _onLogsUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await AutoResponderService.getSettings();
    final hasAccess = await WhatsAppService.hasNotificationAccess();
    final listenerRunning =
        await WhatsAppService.isNotificationListenerRunning();
    final allLists = await DatabaseService.getAllAiLists();

    if (!mounted) return;
    setState(() {
      _isEnabled = settings.isEnabled;
      _instructionsController.text = settings.instructions;
      _selectedTone = settings.tone;
      _learnFromHistory = settings.learnFromHistory;
      _delaySeconds = settings.delaySeconds;
      _targetApp = settings.targetApp;
      _respondMode = settings.respondMode;
      _targetAiList = settings.targetAiList;
      _whitelistController.text = settings.whitelistNumbers;
      _excludedController.text = settings.excludedNumbers;
      _ignoreGroups = settings.ignoreGroups;
      _availableAiLists = {
        'Hot Leads',
        'VIP Customers',
        'Customers',
        'Warm Inquiries',
        'Converted',
        ...allLists,
      }.toList();
      if (!_availableAiLists.contains(_targetAiList)) {
        _availableAiLists.add(_targetAiList);
      }
      _hasNotificationAccess = hasAccess;
      _isNotificationListenerRunning = listenerRunning;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final settings = AutoResponderSettings(
      isEnabled: _isEnabled,
      instructions: _instructionsController.text.trim(),
      tone: _selectedTone,
      learnFromHistory: _learnFromHistory,
      delaySeconds: _delaySeconds,
      targetApp: _targetApp,
      respondMode: _respondMode,
      targetAiList: _targetAiList,
      whitelistNumbers: _whitelistController.text.trim(),
      excludedNumbers: _excludedController.text.trim(),
      ignoreGroups: _ignoreGroups,
    );

    await AutoResponderService.saveSettings(settings);

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Auto-Responder settings saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _runSimulation() async {
    final query = _testMessageController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSimulating = true;
      _simulatedReply = null;
    });

    try {
      final reply = await AutoResponderService.simulateReply(query);
      if (!mounted) return;
      setState(() {
        _simulatedReply = reply ?? '(No response generated. Verify .env GEMINI_API_KEY)';
        _isSimulating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _simulatedReply = 'Error: $e';
        _isSimulating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobi AI Auto-Responder'),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Activation Banner
                  Card(
                    elevation: 0,
                    color: _isEnabled
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _isEnabled
                            ? Colors.green.shade300
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: SwitchListTile(
                      value: _isEnabled,
                      title: Text(
                        _isEnabled
                            ? 'Auto-Responder is ACTIVE'
                            : 'Auto-Responder is OFF',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isEnabled
                              ? Colors.green.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                      subtitle: Text(
                        _isEnabled
                            ? 'Mobi AI listens to WhatsApp notifications & replies in your style'
                            : 'Enable to let Gemini chat automatically with incoming customer messages',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isEnabled ? Colors.green : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 20),
                      ),
                      activeThumbColor: Colors.green.shade700,
                      onChanged: (val) {
                        setState(() => _isEnabled = val);
                        _saveSettings();
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Notification Permission Check Card
                  if (!_hasNotificationAccess) ...[
                    Card(
                      color: Colors.red.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.notifications_active_rounded,
                                    color: Colors.red.shade700, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Notification Access Required',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mobi AI needs Android Notification Access to detect incoming WhatsApp messages and reply automatically in the background.',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.red.shade800),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: () async {
                                    await WhatsAppService
                                        .openNotificationAccessSettings();
                                    _loadSettings();
                                  },
                                  icon: const Icon(Icons.check_circle_outline,
                                      size: 16),
                                  label: const Text('Grant Access',
                                      style: TextStyle(fontSize: 12.5)),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade900,
                                    side: BorderSide(
                                        color: Colors.red.shade300),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () async {
                                    await WhatsAppService
                                        .openAppDetailsSettings();
                                    _loadSettings();
                                  },
                                  icon: const Icon(Icons.settings_outlined,
                                      size: 16),
                                  label: const Text('App Info',
                                      style: TextStyle(fontSize: 12.5)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.red.shade100),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.red.shade800),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Xiaomi / HyperOS / Android 13+: If Android says "Restricted setting", tap "App Info" above -> tap 3 dots (⋮) top right -> "Allow restricted settings" -> then tap "Grant Access".',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else if (!_isNotificationListenerRunning) ...[
                    Card(
                      color: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Notification Access is active. The responder will automatically bind when the next WhatsApp notification arrives.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 1. WhatsApp Application Selection
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366).withAlpha(25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF16A34A),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Target WhatsApp App',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Which WhatsApp installation should auto-respond?',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: ValueKey('targetApp_$_targetApp'),
                            initialValue: _targetApp,
                            decoration: InputDecoration(
                              labelText: 'Active WhatsApp App',
                              prefixIcon: const Icon(Icons.apps_rounded, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'both',
                                child: Text('Both WhatsApp & WhatsApp Business'),
                              ),
                              DropdownMenuItem(
                                value: 'com.whatsapp',
                                child: Text('Regular WhatsApp Only'),
                              ),
                              DropdownMenuItem(
                                value: 'com.whatsapp.w4b',
                                child: Text('WhatsApp Business Only'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _targetApp = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 2. Audience / Recipient Scope Selection
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488).withAlpha(25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_outline_rounded,
                                  color: Color(0xFF0D9488),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-Reply Audience',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Select who is eligible to receive AI responses',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: ValueKey('respondMode_$_respondMode'),
                            initialValue: _respondMode,
                            decoration: InputDecoration(
                              labelText: 'Who Should Receive Auto-Replies?',
                              prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All Numbers (Everyone)'),
                              ),
                              DropdownMenuItem(
                                value: 'unsaved_only',
                                child: Text('Unsaved Numbers Only (New Leads)'),
                              ),
                              DropdownMenuItem(
                                value: 'saved_only',
                                child: Text('Saved Contacts / CRM Leads Only'),
                              ),
                              DropdownMenuItem(
                                value: 'specific_list',
                                child: Text('Specific AI CRM List Only'),
                              ),
                              DropdownMenuItem(
                                value: 'specific_numbers',
                                child: Text('Specific Numbers Only (Whitelist)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _respondMode = val);
                            },
                          ),

                          // If specific_list is selected, show list selector dropdown
                          if (_respondMode == 'specific_list') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey('targetAiList_$_targetAiList'),
                              initialValue: _availableAiLists.contains(_targetAiList)
                                  ? _targetAiList
                                  : (_availableAiLists.isNotEmpty
                                      ? _availableAiLists.first
                                      : 'Hot Leads'),
                              decoration: InputDecoration(
                                labelText: 'Select AI CRM List',
                                prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              items: _availableAiLists
                                  .map((name) => DropdownMenuItem(
                                        value: name,
                                        child: Text(name),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _targetAiList = val);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4),
                              child: Text(
                                'Only contacts assigned to "$_targetAiList" will receive auto-replies.',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ),
                          ],

                          // If specific_numbers is selected, show whitelist textfield
                          if (_respondMode == 'specific_numbers') ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _whitelistController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Allowed Phone Numbers or Names',
                                hintText: '+966501234567, +1234567890, John Doe',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4),
                              child: Text(
                                'Separate numbers or names by comma or new lines. AI will ONLY reply to these.',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. Exclusions & Group Protection Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.block_rounded,
                                  color: Colors.red.shade700,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Exclusions & Group Protection',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Contacts who must NEVER receive auto-replies',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _excludedController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Excluded Numbers or Contact Names',
                              hintText: 'e.g. +966555555555, Dad, Boss, Personal Contact',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                              'Contacts in this list are completely ignored and will never get automated replies.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                          const Divider(height: 24),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _ignoreGroups,
                            activeThumbColor: const Color(0xFF10B981),
                            title: const Text(
                              'Ignore WhatsApp Groups',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: const Text(
                              'Recommended: Do not auto-respond in group chats to prevent spamming groups',
                              style: TextStyle(fontSize: 11),
                            ),
                            onChanged: (val) {
                              setState(() => _ignoreGroups = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Learning from Owner History Toggle
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      value: _learnFromHistory,
                      title: const Text('Learn from My Past Chats',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text(
                        'AI analyzes how you talk across previous chats (tone, greetings, language) and replies exactly like you',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: const Icon(Icons.psychology_outlined,
                          color: Color(0xFF4F46E5)),
                      onChanged: (val) {
                        setState(() => _learnFromHistory = val);
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Business Knowledge / Instructions Input
                  Text(
                    'Business Instructions & Store Knowledge',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tell Mobi AI about your products, pricing, working hours, and policies so it answers accurately.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _instructionsController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. We sell original auto parts. Oil filters are \$15, brake pads \$35. Working hours 9am - 7pm. Delivery available all cities.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tone Preference & Response Delay
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedTone,
                          decoration: InputDecoration(
                            labelText: 'Reply Tone',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: _tones
                              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedTone = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _delaySeconds,
                          decoration: InputDecoration(
                            labelText: 'Reply Delay',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Instant')),
                            DropdownMenuItem(value: 2, child: Text('2 Seconds (Natural)')),
                            DropdownMenuItem(value: 5, child: Text('5 Seconds')),
                            DropdownMenuItem(value: 10, child: Text('10 Seconds')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _delaySeconds = val);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Live Test Simulator Card
                  Card(
                    elevation: 0,
                    color: Colors.indigo.shade50.withAlpha(80),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.indigo.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.smart_toy_outlined, color: Color(0xFF4F46E5)),
                              SizedBox(width: 8),
                              Text(
                                'Test Auto-Responder Simulation',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _testMessageController,
                            decoration: InputDecoration(
                              hintText: 'Type a sample customer question...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              suffixIcon: IconButton(
                                icon: _isSimulating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send_rounded, color: Color(0xFF4F46E5)),
                                onPressed: _isSimulating ? null : _runSimulation,
                              ),
                            ),
                          ),
                          if (_simulatedReply != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Mobi AI Generated Response:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _simulatedReply!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Recent Auto-Replies Activity Log
                  Text(
                    'Recent Auto-Replies (${AutoResponderService.recentLogs.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (AutoResponderService.recentLogs.isEmpty)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No auto-replies dispatched yet.\nIncoming customer messages will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: AutoResponderService.recentLogs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final log = AutoResponderService.recentLogs[i];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      log.senderName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      fmt.format(DateTime.fromMillisecondsSinceEpoch(
                                          log.timestamp)),
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Customer: "${log.incomingMessage}"',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.reply,
                                          size: 14, color: Color(0xFF4F46E5)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          log.replyText,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF312E81),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
