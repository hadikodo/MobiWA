// test/widget_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobiwha/main.dart';
import 'package:mobiwha/services/database_service.dart';
import 'package:mobiwha/services/export_service.dart';
import 'package:mobiwha/models/lead_message.dart';
import 'package:mobiwha/utils/phone_utils.dart';

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

    testDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
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
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
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
              note TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS contacts_cache (
              normalized_phone TEXT PRIMARY KEY,
              display_name TEXT,
              synced_at INTEGER
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
    expect(variants.contains('5552345678'), isTrue);
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

  testWidgets('App smoke test renders navigation shell and dashboard',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MobiWAApp());
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byType(MobiWAApp), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
