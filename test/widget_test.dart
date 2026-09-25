// This file is intentionally minimal.
// The app entry point is MobiWHAApp defined in lib/main.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiwha/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MobiWHAApp());
    expect(find.byType(MobiWHAApp), findsOneWidget);
  });
}
