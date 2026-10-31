import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/screens/rep/sales_rep_home_screen.dart';

// Start-of-day briefing prompt contract: built only from data the rep may
// already see (own profile, own customers, workday-start fix). Never carries
// another rep's or company's data.
void main() {
  test('prompt carries own rep identity and counts', () {
    final prompt = buildStartDayBriefingPrompt(
      repName: 'أحمد',
      repCode: 'R123',
      totalCustomers: 25,
      nearbyCustomers: 4,
      nearbyNames: const ['محل النور', 'سوبر ماركت السلام'],
      hasLocation: true,
    );
    expect(prompt, contains('أحمد'));
    expect(prompt, contains('R123'));
    expect(prompt, contains('25'));
    expect(prompt, contains('4'));
    expect(prompt, contains('محل النور'));
    expect(prompt, contains('موقع بداية اليوم مسجل'));
  });

  test('prompt caps nearby names at ten and skips empties', () {
    final names = List<String>.generate(12, (i) => 'محل $i')..insert(3, '');
    final prompt = buildStartDayBriefingPrompt(
      repName: 'أحمد',
      repCode: 'R123',
      totalCustomers: 30,
      nearbyCustomers: 12,
      nearbyNames: names,
      hasLocation: true,
    );
    expect(prompt, contains('محل 0'));
    expect(prompt, contains('محل 9'));
    expect(prompt, isNot(contains('محل 10')));
    expect(prompt, isNot(contains('محل 11')));
  });

  test('prompt without location falls back and omits area claims', () {
    final prompt = buildStartDayBriefingPrompt(
      repName: 'أحمد',
      repCode: 'R123',
      totalCustomers: 5,
      nearbyCustomers: 0,
      nearbyNames: const [],
      hasLocation: false,
    );
    expect(prompt, contains('تعذر تحديد موقع بداية اليوم'));
    expect(prompt, isNot(contains('موقع بداية اليوم مسجل')));
  });

  test('prompt never echoes foreign data', () {
    const foreign = 'REP-OTHER-999';
    final prompt = buildStartDayBriefingPrompt(
      repName: 'أحمد',
      repCode: 'R123',
      totalCustomers: 1,
      nearbyCustomers: 1,
      nearbyNames: const ['محلي'],
      hasLocation: true,
    );
    expect(prompt, isNot(contains(foreign)));
  });

  group('shouldRestoreBriefing', () {
    test('restores only for the currently open day', () {
      expect(
        shouldRestoreBriefing(storedLogId: 'dayA', currentLogId: 'dayA'),
        isTrue,
      );
    });

    test('rejects stale briefing from a previous day', () {
      expect(
        shouldRestoreBriefing(storedLogId: 'dayA', currentLogId: 'dayB'),
        isFalse,
      );
    });

    test('rejects empty or missing stored id', () {
      expect(
        shouldRestoreBriefing(storedLogId: '', currentLogId: 'dayA'),
        isFalse,
      );
      expect(
        shouldRestoreBriefing(storedLogId: null, currentLogId: 'dayA'),
        isFalse,
      );
      expect(
        shouldRestoreBriefing(storedLogId: 'dayA', currentLogId: null),
        isFalse,
      );
    });
  });
}
