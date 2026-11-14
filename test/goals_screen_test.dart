import 'package:aksab_sales/screens/rep/goals_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins the rep goals screen to the canonical backend field keys so the
// displayed targets always match what distribution writes (notably
// `invoicesTarget`, never a similarly-named wrong key).
void main() {
  group('monthlyGoalValue', () {
    test('reads the five canonical target fields', () {
      final goals = {
        'financialTarget': 10000,
        'hoursTarget': 160,
        'invoicesTarget': 100,
        'clientsTarget': 50,
        'visitsTarget': 200,
      };
      expect(monthlyGoalValue(goals, 'financialTarget'), 10000);
      expect(monthlyGoalValue(goals, 'hoursTarget'), 160);
      expect(monthlyGoalValue(goals, 'invoicesTarget'), 100);
      expect(monthlyGoalValue(goals, 'clientsTarget'), 50);
      expect(monthlyGoalValue(goals, 'visitsTarget'), 200);
    });

    test('returns 0 for missing or null maps, never throws', () {
      expect(monthlyGoalValue(null, 'financialTarget'), 0);
      expect(monthlyGoalValue({}, 'invoicesTarget'), 0);
      expect(monthlyGoalValue({'invoiceTarget': 5}, 'invoicesTarget'), 0);
    });
  });
}
