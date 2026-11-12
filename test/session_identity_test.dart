import 'package:aksab_sales/services/session_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Post-migration identity resolution: when the legacy phone-keyed doc and
// its uid-keyed copy both carry the same uid field, login/session must pick
// the uid-keyed document so holderId == auth uid downstream.
void main() {
  const uid = 'nGgtWSVbCUNQd2Nq4opbRHM1V882';

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryByUid(
    FakeFirebaseFirestore fake,
    String collection,
  ) async {
    final q = await fake.collection(collection).where('uid', isEqualTo: uid).get();
    return q.docs;
  }

  group('pickIdentityDocId', () {
    test('prefers the uid-keyed doc when legacy + migrated docs coexist',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('managers').doc('201021070462').set({
        'uid': uid,
        'role': 'sales_supervisor',
      });
      await fake.collection('managers').doc(uid).set({
        'uid': uid,
        'role': 'sales_supervisor',
      });
      final docs = await queryByUid(fake, 'managers');
      expect(docs.length, 2);
      expect(SessionService.pickIdentityDocId(docs, uid), uid);
    });

    test('keeps the single match when no duplicate exists', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc(uid).set({'uid': uid});
      final docs = await queryByUid(fake, 'salesRep');
      expect(SessionService.pickIdentityDocId(docs, uid), uid);
    });

    test('keeps the legacy doc when it is the only match (pre-migration)',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('201021070461').set({'uid': uid});
      final docs = await queryByUid(fake, 'salesRep');
      expect(
          SessionService.pickIdentityDocId(docs, uid), '201021070461');
    });

    test('returns empty for no matches', () async {
      final fake = FakeFirebaseFirestore();
      final docs = await queryByUid(fake, 'managers');
      expect(SessionService.pickIdentityDocId(docs, uid), '');
    });
  });
}
