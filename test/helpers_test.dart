import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/firestore_helpers.dart';

// Regression tests for role-gated fixes:
// - whereIn chunking (max 10)
// - withdraw validation
// - supervisor/manager target permission (sales_supervisor, not supervisor)
void main() {
  group('chunkList', () {
    test('empty stays empty', () {
      expect(chunkList<String>([]), isEmpty);
    });
    test('splits more than 10 into chunks', () {
      final items = List.generate(25, (i) => 'r$i');
      final chunks = chunkList(items);
      expect(chunks.length, 3);
      expect(chunks.every((c) => c.length <= 10), isTrue);
      expect(chunks.expand((c) => c).toList(), items);
    });
    test('isValidWhereIn rejects empty and >10', () {
      expect(isValidWhereIn<String>([]), isFalse);
      expect(isValidWhereIn(List.generate(10, (i) => '$i')), isTrue);
      expect(isValidWhereIn(List.generate(11, (i) => '$i')), isFalse);
    });
  });

  group('validateWithdrawAmount', () {
    test('rejects zero/negative/over-balance', () {
      expect(validateWithdrawAmount('0', 100), isNotNull);
      expect(validateWithdrawAmount('-5', 100), isNotNull);
      expect(validateWithdrawAmount('200', 100), isNotNull);
      expect(validateWithdrawAmount('abc', 100), isNotNull);
    });
    test('enforces min/max bounds', () {
      expect(validateWithdrawAmount('49', 10000), isNotNull);
      expect(validateWithdrawAmount('100001', 200000), isNotNull);
      expect(validateWithdrawAmount('50', 100), isNull);
      expect(validateWithdrawAmount('100000', 100000), isNull);
    });
    test('accepts valid amount', () {
      expect(validateWithdrawAmount('50', 100), isNull);
    });
  });

  group('validateAccountNumber', () {
    test('accepts Egyptian wallet prefixes', () {
      expect(validateAccountNumber('01012345678'), isNull);
      expect(validateAccountNumber('01112345678'), isNull);
      expect(validateAccountNumber('01212345678'), isNull);
      expect(validateAccountNumber('01512345678'), isNull);
      expect(validateAccountNumber('010 1234 5678'), isNull);
    });
    test('rejects invalid wallet numbers', () {
      expect(validateAccountNumber('123'), isNotNull);
      expect(validateAccountNumber('010123'), isNotNull);
      expect(validateAccountNumber('01612345678'), isNotNull);
      expect(validateAccountNumber('02012345678'), isNotNull);
      expect(validateAccountNumber(''), isNotNull);
    });
  });

  group('hasBlockingPendingRequest', () {
    test('blocks when a pending request exists', () {
      expect(hasBlockingPendingRequest(pendingCount: 1), isTrue);
      expect(hasBlockingPendingRequest(pendingCount: 0), isFalse);
    });
  });

  group('canEditTarget', () {
    test('manager edits managers only', () {
      expect(canEditTarget(myRole: 'sales_manager', collection: 'managers'), isTrue);
      expect(canEditTarget(myRole: 'sales_manager', collection: 'salesRep'), isFalse);
    });
    test('supervisor edits salesRep only (sales_supervisor)', () {
      expect(canEditTarget(myRole: 'sales_supervisor', collection: 'salesRep'), isTrue);
      expect(canEditTarget(myRole: 'supervisor', collection: 'salesRep'), isFalse);
      expect(canEditTarget(myRole: 'sales_supervisor', collection: 'managers'), isFalse);
    });
  });
}
