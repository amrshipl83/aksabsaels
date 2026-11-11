import 'package:aksab_sales/utils/staff_display_name.dart';
import 'package:flutter_test/flutter_test.dart';

// Unified name resolution for target/admin surfaces: top-level keys first,
// then the nested registration profile, then the explicit badge.
void main() {
  group('staffDisplayName', () {
    test('reads top-level fullname', () {
      expect(staffDisplayName({'fullname': 'أحمد محمد'}), 'أحمد محمد');
    });

    test('reads alternative keys and trims whitespace', () {
      expect(staffDisplayName({'fullName': '  سارة  '}), 'سارة');
      expect(staffDisplayName({'name': 'خالد'}), 'خالد');
      expect(staffDisplayName({'displayName': 'منى'}), 'منى');
    });

    test('reads nested profile when top-level is missing', () {
      expect(
        staffDisplayName({'phone': '010', 'profile': {'fullname': 'كريم'}}),
        'كريم',
      );
    });

    test('prefers top-level name over nested profile', () {
      expect(
        staffDisplayName({'fullname': 'ظاهر', 'profile': {'fullname': 'مخفي'}}),
        'ظاهر',
      );
    });

    test('falls back to the explicit badge, never blank/UID/phone', () {
      expect(staffDisplayName({'phone': '010'}), 'بدون اسم');
      expect(staffDisplayName({'uid': 'abc123'}), 'بدون اسم');
      expect(staffDisplayName({'fullname': '   '}), 'بدون اسم');
      expect(staffDisplayName({'profile': {'address': 'القاهرة'}}), 'بدون اسم');
    });
  });
}
