import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/screens/rep/shira_voice_chat_widget.dart';

// Regression: start-of-day briefing messages handed to the Shira sheet as
// initialMessages must actually render in the chat. The FAB frame highlight
// is driven by parent state, so it can light up while the briefing itself
// stays invisible (messages were appended without setState -> no rebuild).
void main() {
  testWidgets('briefing initialMessages are shown in the chat',
      (WidgetTester tester) async {
    final briefing = [
      ChatMessage(text: 'طلب تحليل بداية اليوم', isUser: true),
      ChatMessage(
          text: 'اقتراح: ابدأ بزيارة محل النور أولا', isUser: false),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShiraVoiceChatWidget(
            cloudFunctionUrl: 'https://example.test',
            userRole: 'sales_representative',
            initialMessages: briefing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلب تحليل بداية اليوم'), findsOneWidget);
    expect(
        find.text('اقتراح: ابدأ بزيارة محل النور أولا'), findsOneWidget);
  });
}
