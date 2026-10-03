// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobiwha/main.dart';
import 'package:mobiwha/services/database_service.dart';
import 'package:mobiwha/services/export_service.dart';
import 'package:mobiwha/models/lead_message.dart';
import 'package:mobiwha/services/auto_responder_service.dart';
import 'package:mobiwha/utils/phone_utils.dart';
import 'package:mobiwha/widgets/permissions_prompt_dialog.dart';
import 'package:mobiwha/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database testDb;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Mock permission handler channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return 0; // PermissionStatus.denied
        }
        return null;
      },
    );

    // Mock flutter_contacts channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('github.com/Quis/flutter_contacts'),
      (MethodCall methodCall) async {
        return null;
      },
    );

    // Mock notification_capture channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mobiwha.mobiwha/notification_capture'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'hasNotificationAccess') return false;
        if (methodCall.method == 'openNotificationAccessSettings') return true;
        if (methodCall.method == 'openAppDetailsSettings') return true;
        if (methodCall.method == 'isNotificationListenerRunning') return false;
        if (methodCall.method == 'takeSharedWhatsAppExport') return null;
        if (methodCall.method == 'drainCapturedMessages') return <Map>[];
        return null;
      },
    );

    // Mock whatsapp channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mobiwha.mobiwha/whatsapp'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'hasAccessibilityAccess') return false;
        if (methodCall.method == 'getInstalledWhatsAppApps') return <Map>[];
        return null;
      },
    );

    testDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS leads (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              phone_number TEXT NOT NULL UNIQUE,
              name TEXT,
              notes TEXT,
              status TEXT DEFAULT 'New',
              is_unsaved INTEGER DEFAULT 1,
              tags TEXT,
              whatsapp_opt_in INTEGER NOT NULL DEFAULT 0,
              whatsapp_consent_updated_at INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              ai_list TEXT DEFAULT '',
              ai_summary TEXT DEFAULT '',
              ai_next_action TEXT DEFAULT '',
              ai_analyzed_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              lead_id INTEGER NOT NULL,
              phone_number TEXT NOT NULL,
              message TEXT NOT NULL,
              direction TEXT DEFAULT 'incoming',
              timestamp INTEGER NOT NULL,
              note TEXT,
              source_key TEXT UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS contacts_cache (
              normalized_phone TEXT PRIMARY KEY,
              display_name TEXT,
              synced_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_preferences (
              preference_key TEXT PRIMARY KEY,
              preference_value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              phone_number TEXT NOT NULL,
              sender TEXT NOT NULL,
              message TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              package_name TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'unmatched',
              note TEXT,
              source_key TEXT UNIQUE,
              created_at INTEGER NOT NULL,
              matched_lead_id INTEGER
            )
          ''');
        },
      ),
    );
    DatabaseService.setDatabaseForTesting(testDb);
  });

  setUp(() async {
    await testDb.delete('messages');
    await testDb.delete('leads');
    await testDb.delete('contacts_cache');
    await testDb.delete('app_preferences');
    await testDb.delete('pending_notifications');
  });

  tearDownAll(() async {
    await testDb.close();
    DatabaseService.setDatabaseForTesting(null);
  });

  test('PhoneUtils normalization and variants test', () {
    const raw = '+1 (555) 234-5678';
    expect(PhoneUtils.normalize(raw), '+15552345678');
    expect(PhoneUtils.digitsOnly(raw), '15552345678');
    expect(PhoneUtils.looksLikePhoneNumber(raw), isTrue);

    final variants = PhoneUtils.getVariants(raw);
    expect(variants.contains('15552345678'), isTrue);
  });

  test('Database CRUD operations for Leads and Messages', () async {
    // 1. Create a lead
    final lead = await DatabaseService.getOrCreateLead(
      phoneNumber: '+19876543210',
      name: 'Test Enterprise',
      notes: 'Initial inquiry test',
      status: 'New',
      isUnsaved: true,
    );

    expect(lead.id, isNotNull);
    expect(lead.phoneNumber, '+19876543210');
    expect(lead.name, 'Test Enterprise');

    // 2. Add message to lead
    final msgId = await DatabaseService.insertMessage(
      LeadMessage(
        leadId: lead.id!,
        phoneNumber: lead.phoneNumber,
        message: 'Hello, need quotation',
        direction: 'incoming',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        note: 'Customer via messaging',
      ),
    );

    expect(msgId, isPositive);

    // 3. Retrieve messages
    final messages = await DatabaseService.getMessagesForLead(lead.id!);
    expect(messages.length, 1);
    expect(messages.first.message, 'Hello, need quotation');

    // 4. Check statistics
    final stats = await DatabaseService.getStats();
    expect(stats['totalLeads']!, 1);
    expect(stats['totalMessages']!, 1);

    // 5. Search leads
    final searchResults = await DatabaseService.getLeads(query: 'Enterprise');
    expect(searchResults.any((l) => l.phoneNumber == '+19876543210'), isTrue);
  });

  test('ExportService CSV import test', () async {
    const csvContent =
        "Phone,Name,Status,Notes\n+1000000001,Acme Corp,Qualified,Important lead\n+1000000002,Global Logistics,New,Needs catalog";

    final count = await ExportService.importLeadsFromCSV(csvContent);
    expect(count, 2);

    final lead = await DatabaseService.getLeadByPhone('+1000000001');
    expect(lead, isNotNull);
    expect(lead!.name, 'Acme Corp');
    expect(lead.status, 'Qualified');
  });

  test('Mobi AI CRM lists categorization and counting test', () async {
    final lead1 = await DatabaseService.getOrCreateLead(
      phoneNumber: '+11111111111',
      name: 'Hot Lead Buyer',
      status: 'Qualified',
    );
    final lead2 = await DatabaseService.getOrCreateLead(
      phoneNumber: '+22222222222',
      name: 'VIP Client',
      status: 'Converted',
    );

    // Assign to Mobi AI CRM lists
    await DatabaseService.setLeadAiList(lead1.id!, 'Hot Leads');
    await DatabaseService.setLeadAiList(lead2.id!, 'VIP Customers');

    final counts = await DatabaseService.getAiListCounts();
    expect(counts['Hot Leads'], 1);
    expect(counts['VIP Customers'], 1);

    // Test idempotent scraped messages insertion
    final inserted = await DatabaseService.insertScrapedMessages(
      lead1.id!,
      lead1.phoneNumber,
      [
        {
          'message': 'Interested in placing order for 10 units',
          'direction': 'incoming',
          'time': '10:30 AM',
        },
      ],
    );
    expect(inserted, 1);

    // Inserting identical message again should be ignored (no duplicates)
    final reinserted = await DatabaseService.insertScrapedMessages(
      lead1.id!,
      lead1.phoneNumber,
      [
        {
          'message': 'Interested in placing order for 10 units',
          'direction': 'incoming',
          'time': '10:30 AM',
        },
      ],
    );
    expect(reinserted, 0);
  });

  test('Lead multi-list parsing and dynamic list filtering test', () async {
    // 1. Create a lead with multiple AI lists (e.g., bought oil filter)
    final lead = await DatabaseService.getOrCreateLead(
      phoneNumber: '+19998887777',
      name: 'Ahmed Oil Buyer',
      status: 'Qualified',
    );

    // Multi-list assignment (e.g. Customers, Oil Filter Customers, VIP Customers)
    await DatabaseService.setLeadAiList(
      lead.id!,
      'Customers, Oil Filter Customers, VIP Customers',
    );

    final updatedLead = await DatabaseService.getLeadByPhone('+19998887777');
    expect(updatedLead, isNotNull);
    expect(updatedLead!.aiLists, contains('Customers'));
    expect(updatedLead.aiLists, contains('Oil Filter Customers'));
    expect(updatedLead.aiLists, contains('VIP Customers'));
    expect(updatedLead.isInList('Oil Filter Customers'), isTrue);
    expect(updatedLead.isInList('Customers'), isTrue);
    expect(updatedLead.isInList('Brake Pads'), isFalse);

    // 2. Querying by specific list name should find the lead
    final oilFilterLeads = await DatabaseService.getLeads(aiList: 'Oil Filter Customers');
    expect(oilFilterLeads.any((l) => l.phoneNumber == '+19998887777'), isTrue);

    final generalCustomerLeads = await DatabaseService.getLeads(aiList: 'Customers');
    expect(generalCustomerLeads.any((l) => l.phoneNumber == '+19998887777'), isTrue);

    // 3. Test adding and removing individual lists dynamically
    await DatabaseService.addLeadToList(lead.id!, 'Brake Pads');
    final withBrakePads = await DatabaseService.getLeadByPhone('+19998887777');
    expect(withBrakePads!.isInList('Brake Pads'), isTrue);

    await DatabaseService.removeLeadFromList(lead.id!, 'VIP Customers');
    final withoutVip = await DatabaseService.getLeadByPhone('+19998887777');
    expect(withoutVip!.isInList('VIP Customers'), isFalse);
    expect(withoutVip.isInList('Oil Filter Customers'), isTrue);

    // 4. Check getAllAiLists returns all individual lists
    final allLists = await DatabaseService.getAllAiLists();
    expect(allLists, contains('Customers'));
    expect(allLists, contains('Oil Filter Customers'));
    expect(allLists, contains('Brake Pads'));
  });

  test('AutoResponder settings persistence and owner style sampling test', () async {
    // 1. Initial settings should default to false
    final initial = await AutoResponderService.getSettings();
    expect(initial.isEnabled, isFalse);

    // 2. Save new settings
    await AutoResponderService.saveSettings(
      const AutoResponderSettings(
        isEnabled: true,
        instructions: 'Only speak Arabic and recommend original parts',
        tone: 'Friendly & Casual',
        learnFromHistory: true,
        delaySeconds: 5,
        replyToAll: true,
      ),
    );

    final loaded = await AutoResponderService.getSettings();
    expect(loaded.isEnabled, isTrue);
    expect(loaded.instructions, 'Only speak Arabic and recommend original parts');
    expect(loaded.tone, 'Friendly & Casual');
    expect(loaded.delaySeconds, 5);

    // 3. Owner style sampling: populate some outgoing messages
    final lead = await DatabaseService.getOrCreateLead(
      phoneNumber: '+15550001111',
      name: 'Salim Client',
    );
    await DatabaseService.insertMessage(
      LeadMessage(
        leadId: lead.id!,
        phoneNumber: lead.phoneNumber,
        message: 'أهلاً وسهلاً بك، الفلتر متوفر بـ 50 ريال',
        direction: 'outgoing',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        note: 'Manual response',
      ),
    );
    await DatabaseService.insertMessage(
      LeadMessage(
        leadId: lead.id!,
        phoneNumber: lead.phoneNumber,
        message: 'تفضل في أي وقت، المتجر يفتح الساعة 9 صباحاً',
        direction: 'outgoing',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final samples = await AutoResponderService.getOwnerStyleSamples(limit: 5);
    expect(samples.length, 2);
    expect(samples.any((s) => s.contains('متوفر')), isTrue);

    // 4. Test simulateReply
    final simReply = await AutoResponderService.simulateReply('Hello, how much is the filter?');
    expect(simReply, isNotNull);
  });

  test('AutoResponder granular filtering rules (target app, exclusions, whitelist, lists, groups)', () async {
    // 1. Target WhatsApp package filtering
    const waBusinessOnly = AutoResponderSettings(
      isEnabled: true,
      targetApp: 'com.whatsapp.w4b',
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: waBusinessOnly,
        sender: 'Inquirer',
        phone: '+1234567890',
        packageName: 'com.whatsapp.w4b',
      ),
      isTrue,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: waBusinessOnly,
        sender: 'Inquirer',
        phone: '+1234567890',
        packageName: 'com.whatsapp',
      ),
      isFalse,
    );

    // 2. Group chat protection
    const groupProtected = AutoResponderSettings(
      isEnabled: true,
      ignoreGroups: true,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: groupProtected,
        sender: 'Inquirer',
        phone: '+1234567890',
        isGroup: true,
      ),
      isFalse,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: groupProtected,
        sender: 'Inquirer',
        phone: '+1234567890',
        isGroup: false,
      ),
      isTrue,
    );

    // 3. Blacklist / Excluded numbers or names
    const withExclusion = AutoResponderSettings(
      isEnabled: true,
      excludedNumbers: '+19991112222, Boss, Family Group',
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: withExclusion,
        sender: 'Random Customer',
        phone: '+19991112222',
      ),
      isFalse,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: withExclusion,
        sender: 'Boss',
        phone: '+10000000000',
      ),
      isFalse,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: withExclusion,
        sender: 'Random Customer',
        phone: '+15556667777',
      ),
      isTrue,
    );

    // 4. Respond Mode: specific_numbers (Whitelist)
    const whitelistMode = AutoResponderSettings(
      isEnabled: true,
      respondMode: 'specific_numbers',
      whitelistNumbers: '+15553334444, VIP Partner',
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: whitelistMode,
        sender: 'Stranger',
        phone: '+10000000000',
      ),
      isFalse,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: whitelistMode,
        sender: 'VIP Partner',
        phone: '+10000000000',
      ),
      isTrue,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: whitelistMode,
        sender: 'Inquirer',
        phone: '+15553334444',
      ),
      isTrue,
    );

    // 5. Respond Mode: specific_list
    final leadInList = await DatabaseService.getOrCreateLead(
      phoneNumber: '+17778889999',
      name: 'Filter Buyer',
    );
    await DatabaseService.setLeadAiList(leadInList.id!, 'Oil Filter Customers');
    final freshLeadInList = await DatabaseService.getLeadByPhone('+17778889999');

    final leadNotInList = await DatabaseService.getOrCreateLead(
      phoneNumber: '+17770001111',
      name: 'General Buyer',
    );
    await DatabaseService.setLeadAiList(leadNotInList.id!, 'Brake Pads');
    final freshLeadNotInList = await DatabaseService.getLeadByPhone('+17770001111');

    const listMode = AutoResponderSettings(
      isEnabled: true,
      respondMode: 'specific_list',
      targetAiList: 'Oil Filter Customers',
    );

    expect(
      AutoResponderService.shouldRespond(
        settings: listMode,
        sender: 'Filter Buyer',
        phone: '+17778889999',
        lead: freshLeadInList,
      ),
      isTrue,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: listMode,
        sender: 'General Buyer',
        phone: '+17770001111',
        lead: freshLeadNotInList,
      ),
      isFalse,
    );

    // 6. Respond Mode: unsaved_only
    const unsavedMode = AutoResponderSettings(
      isEnabled: true,
      respondMode: 'unsaved_only',
    );
    final savedLead = await DatabaseService.getOrCreateLead(
      phoneNumber: '+14445556666',
      name: 'Saved Friend',
      isUnsaved: false,
    );
    expect(
      AutoResponderService.shouldRespond(
        settings: unsavedMode,
        sender: 'Saved Friend',
        phone: '+14445556666',
        lead: savedLead,
      ),
      isFalse,
    );
  });

  testWidgets('SplashScreen renders logo and title',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(autoNavigate: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Mobi AI'), findsOneWidget);
    expect(find.text('Autonomous WhatsApp CRM'), findsOneWidget);
  });

  testWidgets('App smoke test renders navigation shell and dashboard',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MobiWAApp(skipSplash: true));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byType(MobiWAApp), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('PermissionsPromptDialog renders all 3 permission items and actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PermissionsPromptDialog(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Permissions Setup'), findsOneWidget);
    expect(find.text('Device Contacts'), findsOneWidget);
    expect(find.text('Notification Access'), findsOneWidget);
    expect(find.text('WhatsApp Chat Reader'), findsOneWidget);
    expect(find.text('Continue Anyway'), findsOneWidget);
  });
}
