import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiwha/widgets/phone_contact_picker.dart';
import 'package:mobiwha/core/phone.dart';
import 'package:mobiwha/core/theme.dart';
import 'package:mobiwha/data/auth.dart';
import 'package:mobiwha/data/models.dart';
import 'package:mobiwha/screens/admin/activity_chart.dart';
import 'package:mobiwha/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('Phone', () {
    test('keeps international numbers', () {
      expect(Phone.normalize('+961 70 123 456'), '+96170123456');
      expect(Phone.normalize('00961-70-123456'), '+96170123456');
    });

    test('applies the country code to local numbers', () {
      expect(Phone.normalize('70 123 456', defaultCountryCode: '961'), '+96170123456');
      expect(Phone.normalize('03 123 456', defaultCountryCode: '961'), '+9613123456');
    });

    test('accepts Arabic-Indic digits', () {
      expect(Phone.normalize('+٩٦١٧٠١٢٣٤٥٦'), '+96170123456');
    });

    test('rejects junk', () {
      expect(Phone.normalize('hello'), isNull);
      expect(Phone.normalize('12345'), isNull);
    });

    test('parses pasted lists and removes duplicates', () {
      final r = Phone.parseList('+96170123456\n+961 70 123 456, abc; +4915112345678');
      expect(r.valid, ['+96170123456', '+4915112345678']);
      expect(r.invalid, ['abc']);
    });
  });

  group('Auth', () {
    test('plain usernames map to the app email domain, emails stay as they are', () {
      expect(Auth.emailFor(' Ali.Shop '), 'ali.shop@users.mobiwa.app');
      expect(Auth.emailFor('Hadi.Jaber@SupertechLB.com'), 'hadi.jaber@supertechlb.com');
    });
  });

  group('Models', () {
    test('category reads the embedded contact count', () {
      final c = ContactCategory.fromRow({
        'id': 7,
        'user_id': 'u1',
        'name': 'Car Parts',
        'kind': 'custom',
        'description': '',
        'contacts': [
          {'count': 12}
        ],
      });
      expect(c.count, 12);
      expect(c.isSystem, isFalse);
    });

    test('user stats parse from the admin RPC row', () {
      final s = UserStats.fromRow({
        'user_id': 'u1',
        'username': 'ali',
        'role': 'admin',
        'active': true,
        'numbers': 40,
        'customers': 25,
        'junk': 10,
        'unnamed': 5,
        'categories': 3,
        'messages_sent': 99,
      });
      expect(s.profile.isAdmin, isTrue);
      expect(s.profile.id, 'u1');
      expect(s.messagesSent, 99);
    });
  });

  testWidgets('Login asks for username and password', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const LoginScreen()));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('Activity chart shows the total, and a day when a bar is tapped', (tester) async {
    final today = DateTime(2026, 11, 23);
    final days = [
      for (var i = 13; i >= 0; i--)
        DayActivity(today.subtract(Duration(days: i)), 0, 0, i == 0 ? 7 : 1),
    ];
    await tester.pumpWidget(
        _app(Padding(padding: const EdgeInsets.all(16), child: ActivityChart(days: days))));
    expect(find.text('20'), findsOneWidget); // 13 × 1 + 7
    expect(find.text('Nov 23'), findsNothing);
    // Tap today's column (the last bar hit area).
    final bars = find.descendant(of: find.byType(ActivityChart), matching: find.byType(GestureDetector));
    await tester.tap(bars.last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nov 23'), findsOneWidget);
    expect(find.text('20'), findsNothing); // headline switched from the total to the day
  });

  testWidgets('Login legal links fit a small phone', (tester) async {
    tester.view.physicalSize = const Size(720, 1520); // 360×760 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const LoginScreen()));
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow
  });

  testWidgets('Phone contact picker filters WhatsApp contacts and selects all', (tester) async {
    // A returning user who already accepted the contacts disclosure.
    SharedPreferences.setMockInitialValues({'disclosure_contacts_v1': true});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.mobiwha/automation'),
      (call) async => switch (call.method) {
        'requestContactsPermission' => 'granted',
        'getPhoneContacts' => [
            {'name': 'Ali', 'phone': '+96170000001', 'whatsapp': true, 'business': false},
            {'name': 'Rana', 'phone': '+96170000002', 'whatsapp': true, 'business': true},
            {'name': 'Landline', 'phone': '01 234 567', 'whatsapp': false, 'business': false},
          ],
        _ => null,
      },
    );

    List<PhoneContact>? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => result = await pickPhoneContacts(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Default filter: only WhatsApp contacts.
    expect(find.text('On WhatsApp · 2'), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Landline'), findsNothing);

    await tester.tap(find.text('Select all 2 shown'));
    await tester.pump();
    await tester.tap(find.text('Done · 2 selected'));
    await tester.pumpAndSettle();
    expect(result!.map((c) => c.name), ['Ali', 'Rana']);
  });
}
