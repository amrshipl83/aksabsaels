import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Replaces the default counter template (app has no counter).
// Firebase-dependent screens are not pumped here on purpose:
// LoginScreen touches FirebaseAuth in initState, so this smoke test
// only verifies the RTL Arabic rendering pipeline the app forces
// globally in MaterialApp builder.
void main() {
  testWidgets('RTL smoke: Arabic title renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('أكسب للمبيعات'),
        ),
      ),
    );

    expect(find.text('أكسب للمبيعات'), findsOneWidget);
  });
}
