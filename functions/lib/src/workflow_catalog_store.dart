import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'workflow_catalog.dart';
import 'workspace_store.dart';

extension WorkspaceWorkflowCatalogs on WorkspaceStore {
  Future<void> saveWorkflowCatalog(
    String workspaceId,
    WorkflowCatalog catalog,
  ) async {
    await firestore
        .collection('workflowCatalogs')
        .doc(_catalogDocumentId(workspaceId, catalog.repository))
        .set({
          ...catalog.toJson(),
          'workspaceId': workspaceId,
          'fetchedAt': Timestamp.now(),
        });
  }

  Future<List<WorkflowCatalog>> listWorkflowCatalogs(String workspaceId) async {
    final snapshots = await firestore
        .collection('workflowCatalogs')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    final catalogs = snapshots.docs
        .map((snapshot) => WorkflowCatalog.fromJson(snapshot.data()))
        .toList();
    catalogs.sort((left, right) => left.repository.compareTo(right.repository));
    return catalogs;
  }

  Future<WorkflowCatalog> getWorkflowCatalog(
    String workspaceId,
    String repository,
  ) async {
    final snapshot = await firestore
        .collection('workflowCatalogs')
        .doc(_catalogDocumentId(workspaceId, repository))
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'workflow_catalog_not_found',
        'Refresh workflow discovery before launching this workflow.',
      );
    }
    return WorkflowCatalog.fromJson(data);
  }

  Future<void> deleteWorkflowCatalog(
    String workspaceId,
    String repository,
  ) async {
    await firestore
        .collection('workflowCatalogs')
        .doc(_catalogDocumentId(workspaceId, repository))
        .delete();
  }

  Future<void> removeWorkflowCatalogsOutside(
    String workspaceId,
    Set<String> repositories,
  ) async {
    final snapshots = await firestore
        .collection('workflowCatalogs')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    final batch = firestore.batch();
    var changed = false;
    for (final snapshot in snapshots.docs) {
      if (!repositories.contains(snapshot.data()['repository'])) {
        batch.delete(snapshot.ref);
        changed = true;
      }
    }
    if (changed) await batch.commit();
  }
}

String workflowKey(String repository, String workflowId) =>
    '$repository#$workflowId';

({String repository, String workflowId}) parseWorkflowKey(String value) {
  final split = value.lastIndexOf('#');
  if (split <= 0 || split == value.length - 1) {
    throw const ApiError(
      400,
      'invalid_workflow',
      'Select a discovered workflow.',
    );
  }
  final repository = value.substring(0, split);
  final workflowId = value.substring(split + 1);
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository) ||
      !RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(workflowId)) {
    throw const ApiError(
      400,
      'invalid_workflow',
      'Select a discovered workflow.',
    );
  }
  return (repository: repository, workflowId: workflowId);
}

String _catalogDocumentId(String workspaceId, String repository) {
  final digest = sha256.convert(utf8.encode(repository)).toString();
  return '${workspaceId}_$digest';
}
