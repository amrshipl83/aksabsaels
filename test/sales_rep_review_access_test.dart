import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/services/sales_rep_review_access.dart';

void main() {
  group('SalesRepReviewAccess allowlist', () {
    test('all three review numbers reach the review path (local form)', () {
      expect(SalesRepReviewAccess.isReviewNumber('01021070462'), isTrue);
      expect(SalesRepReviewAccess.isReviewNumber('01021070461'), isTrue);
      expect(SalesRepReviewAccess.isReviewNumber('01021070463'), isTrue);
    });

    test('international and spaced formats normalize to the same numbers', () {
      expect(SalesRepReviewAccess.normalize('201021070462'), '01021070462');
      expect(SalesRepReviewAccess.normalize('+201021070461'), '01021070461');
      expect(SalesRepReviewAccess.normalize('00201021070463'), '01021070463');
      expect(SalesRepReviewAccess.normalize('010 2107 0462'), '01021070462');
      expect(SalesRepReviewAccess.isReviewNumber('201021070461'), isTrue);
    });

    test('unlisted numbers stay on the Akedly path', () {
      expect(SalesRepReviewAccess.isReviewNumber('01000000000'), isFalse);
      expect(SalesRepReviewAccess.isReviewNumber('01111111111'), isFalse);
      expect(SalesRepReviewAccess.isReviewNumber(''), isFalse);
      expect(SalesRepReviewAccess.isReviewNumber('123'), isFalse);
      // Neighboring numbers must not match by pattern.
      expect(SalesRepReviewAccess.isReviewNumber('01021070460'), isFalse);
      expect(SalesRepReviewAccess.isReviewNumber('01021070464'), isFalse);
    });

    test('My Test App review numbers are NOT in the Sales Rep list', () {
      // No overlap with the other app's accounts on the same Firebase project.
      expect(SalesRepReviewAccess.isReviewNumber('01278287168'), isFalse);
      expect(SalesRepReviewAccess.isReviewNumber('01551445210'), isFalse);
    });
  });

  group('SalesRepReviewAccess fixed code', () {
    test('only 123456 in exact order is accepted', () {
      expect(SalesRepReviewAccess.isValidReviewCode('123456'), isTrue);
      expect(SalesRepReviewAccess.isValidReviewCode(' 123456 '), isTrue);
    });

    test('wrong codes fail', () {
      expect(SalesRepReviewAccess.isValidReviewCode('000000'), isFalse);
      expect(SalesRepReviewAccess.isValidReviewCode('654321'), isFalse);
      expect(SalesRepReviewAccess.isValidReviewCode('12345'), isFalse);
      expect(SalesRepReviewAccess.isValidReviewCode('1234567'), isFalse);
      expect(SalesRepReviewAccess.isValidReviewCode(''), isFalse);
    });
  });

  group('SalesRepReviewAccess credential namespace', () {
    test('review emails never collide with My Test App identities', () {
      for (final phone in SalesRepReviewAccess.reviewPhones) {
        final email = SalesRepReviewAccess.reviewEmail(phone);
        // My Test App uses '<phone>@aksab.com' — disjoint by construction.
        expect(email, isNot('$phone@aksab.com'));
        expect(email.contains('@aksab.com'), isFalse);
      }
    });

    test('review password scheme differs from My Test App Rabia_ scheme', () {
      for (final phone in SalesRepReviewAccess.reviewPhones) {
        final password =
            SalesRepReviewAccess.reviewPassword(phone);
        expect(password.startsWith('Rabia_'), isFalse);
        expect(password, isNot('123456'));
        expect(password.length, greaterThanOrEqualTo(6));
      }
    });

    test('each review number maps to its documented role and collection', () {
      expect(SalesRepReviewAccess.reviewRoles['01021070462'], 'sales_rep');
      expect(SalesRepReviewAccess.reviewRoles['01021070461'], 'sales_supervisor');
      expect(SalesRepReviewAccess.reviewRoles['01021070463'], 'sales_manager');
      expect(SalesRepReviewAccess.expectedCollection('sales_rep'), 'salesRep');
      expect(
          SalesRepReviewAccess.expectedCollection('sales_supervisor'), 'managers');
      expect(
          SalesRepReviewAccess.expectedCollection('sales_manager'), 'managers');
    });
  });
}
