import 'package:google_cloud_firestore/google_cloud_firestore.dart';

/// Point-document fixture. Transactions commit together; no provider traffic.
final class CredentialFirestoreFake implements Firestore {
  final documents = <String, Map<String, Object?>>{};
  int reads = 0;
  int writes = 0;
  final transactionAttempts = <int>[];
  final _versions = <String, int>{};

  @override
  CollectionReference<Map<String, Object?>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> updateFunction, {
    TransactionOptions? transactionOptions,
  }) async {
    transactionAttempts.add(transactionOptions?.maxAttempts ?? 5);
    final transaction = _Transaction(this);
    final result = await updateFunction(transaction);
    if (transaction.versions.entries.any(
      (entry) => (_versions[entry.key] ?? 0) != entry.value,
    )) {
      throw StateError('Fixture transaction conflict; no automatic retry.');
    }
    for (final write in transaction.pending.entries) {
      documents[write.key] = write.value;
      _versions[write.key] = (_versions[write.key] ?? 0) + 1;
      writes++;
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected Firestore operation.');
}

final class _Collection implements CollectionReference<Map<String, Object?>> {
  const _Collection(this.owner, this.path);
  final CredentialFirestoreFake owner;
  @override
  final String path;
  @override
  DocumentReference<Map<String, Object?>> doc([String? documentPath]) =>
      _Document(owner, '$path/$documentPath');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected collection operation.');
}

final class _Document implements DocumentReference<Map<String, Object?>> {
  const _Document(this.owner, this.path);
  final CredentialFirestoreFake owner;
  @override
  final String path;
  @override
  CollectionReference<Map<String, Object?>> collection(String path) =>
      _Collection(owner, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, Object?>>> get() async {
    owner.reads++;
    return _Snapshot(owner.documents[path]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected document operation.');
}

final class _Snapshot<T> implements DocumentSnapshot<T> {
  const _Snapshot(this.value);
  final T? value;
  @override
  T? data() => value;
  @override
  bool get exists => value != null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected snapshot operation.');
}

final class _Transaction implements Transaction {
  _Transaction(this.owner);
  final CredentialFirestoreFake owner;
  final pending = <String, Map<String, Object?>>{};
  final versions = <String, int>{};
  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> docRef) async {
    owner.reads++;
    if (pending.isNotEmpty) throw StateError('Read after write.');
    versions[docRef.path] = owner._versions[docRef.path] ?? 0;
    return _Snapshot(owner.documents[docRef.path] as T?);
  }

  @override
  void set<T>(DocumentReference<T> docRef, T data, {SetOptions? options}) {
    pending[docRef.path] = {
      if (options != null) ...?owner.documents[docRef.path],
      ...(data as Map<String, Object?>),
    };
  }

  @override
  void update(
    DocumentReference<dynamic> docRef,
    Map<Object?, Object?> data, {
    Precondition? precondition,
  }) => set(
    docRef,
    data.cast<String, Object?>(),
    options: const SetOptions.merge(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected transaction operation.');
}
