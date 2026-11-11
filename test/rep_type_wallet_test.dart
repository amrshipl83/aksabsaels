import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/firestore_helpers.dart';

// Phase-1 rep classification gating (repType on the approved salesRep doc):
// 1. new permanent rep → no wallet, no access
// 2. new freelance rep → wallet shown and accessible
// 3. legacy rep (approved before classification) → treated as permanent
// 4. missing/unknown type for any reason → never granted wallet access
void main() {
  group('normalizeRepType', () {
    test('freelance stays freelance', () {
      expect(normalizeRepType('freelance'), kRepTypeFreelance);
    });
    test('permanent stays permanent', () {
      expect(normalizeRepType('permanent'), kRepTypePermanent);
    });
    test('missing type defaults to permanent (case 3+4)', () {
      expect(normalizeRepType(null), kRepTypePermanent);
      expect(normalizeRepType(''), kRepTypePermanent);
    });
    test('unknown values never escalate to freelance', () {
      expect(normalizeRepType('admin'), kRepTypePermanent);
      expect(normalizeRepType('FREELANCE'), kRepTypePermanent);
      expect(normalizeRepType(42), kRepTypePermanent);
    });
  });

  group('canViewGoals', () {
    test('permanent rep sees goals', () {
      expect(canViewGoals('permanent'), isTrue);
    });
    test('freelance rep is excluded from goals', () {
      expect(canViewGoals('freelance'), isFalse);
    });
    test('legacy rep without type sees goals', () {
      expect(canViewGoals(null), isTrue);
    });
  });

  group('isTargetEligible', () {
    test('only permanent (incl. legacy) enter distribution/tracking', () {
      expect(isTargetEligible('permanent'), isTrue);
      expect(isTargetEligible(null), isTrue);
      expect(isTargetEligible('freelance'), isFalse);
    });
  });

  group('canAccessWallet', () {
    test('case 1: new permanent rep is denied', () {
      expect(canAccessWallet('permanent'), isFalse);
    });
    test('case 2: new freelance rep is allowed', () {
      expect(canAccessWallet('freelance'), isTrue);
    });
    test('case 3: legacy rep without type is denied', () {
      expect(canAccessWallet(null), isFalse);
    });
    test('case 4: undetermined type is denied', () {
      expect(canAccessWallet(''), isFalse);
      expect(canAccessWallet('whatever'), isFalse);
    });
  });
}
