import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:breathe_garden_flutter/main.dart';
import 'package:breathe_garden_flutter/src/config.dart';

void main() {
  testWidgets('PreTra requires clear consent before enabling capture', (
    WidgetTester tester,
  ) async {
    const config = AppConfig(apiKey: '', simulatedRequested: true, isDev: true);

    await tester.pumpWidget(const PreTraApp(config: config));

    expect(find.text('PRETRA'), findsOneWidget);
    expect(find.text('Launch PreTra Session'), findsOneWidget);
    final buttonFinder = find.ancestor(
      of: find.text('Launch PreTra Session'),
      matching: find.byType(ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNull);

    final consentFinder = find.text('I agree to start a webcam session');
    await tester.ensureVisible(consentFinder);
    await tester.tap(consentFinder);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNotNull);
  });
}
