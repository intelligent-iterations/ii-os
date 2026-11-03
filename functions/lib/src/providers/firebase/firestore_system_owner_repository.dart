import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import '../../provider_contracts/identity_provider.dart';

final class FirestoreSystemOwnerRepository implements SystemOwnerRepository {
  const FirestoreSystemOwnerRepository(this.firestore);

  final Firestore firestore;

  @override
  Future<bool> contains(String subject) async =>
      (await firestore.collection('systemOwners').doc(subject).get()).exists;

  @override
  Future<void> grant({required String subject, required String email}) async {
    await firestore.collection('systemOwners').doc(subject).set({
      'uid': subject,
      'email': email,
      'grantedAt': Timestamp.now(),
      'source': 'bootstrap_allowlist',
    });
  }
}
