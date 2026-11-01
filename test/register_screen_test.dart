import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/screens/auth/register_screen.dart';

// Request-first registration form builds offline: role widgets render and
// no OTP dialog exists before submit. Pure widget smoke test.
void main() {
  testWidgets('register screen shows the request form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.pump();
    expect(find.text('إرسال طلب الانضمام'), findsOneWidget);
    expect(find.text('مندوب مبيعات'), findsOneWidget);
    expect(find.text('كود التفعيل'), findsNothing);
  });
}
