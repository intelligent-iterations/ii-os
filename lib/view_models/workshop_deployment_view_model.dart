import 'package:stacked/stacked.dart';

import '../models/workshop_ticket.dart';
import '../repositories/workshop_repository.dart';

/// Owns the visible handoff between a human's Deploy confirmation and the
/// refreshed server receipt that identifies the exact workflow run.
final class WorkshopDeploymentViewModel extends BaseViewModel {
  WorkshopDeploymentViewModel(this._repository);

  final WorkshopRepository _repository;

  String _busyKey(String itemId) => 'deploy:$itemId';
  String _resetBusyKey(String itemId) => 'reset:$itemId';

  bool deploying(String itemId) => busy(_busyKey(itemId));
  bool resetting(String itemId) => busy(_resetBusyKey(itemId));

  Future<void> selectProfile({
    required String workspaceId,
    required WorkshopTicket ticket,
    required String permissionProfile,
    required String permissionRef,
  }) => _repository.selectProfile(
    workspaceId: workspaceId,
    ticket: ticket,
    permissionProfile: permissionProfile,
    permissionRef: permissionRef,
  );

  Future<void> deploy({
    required String workspaceId,
    required String projectId,
    required WorkshopTicket ticket,
    String response = '',
  }) async {
    final key = _busyKey(ticket.itemId);
    if (busy(key)) return;
    setError(null);
    setBusyForObject(key, true);
    try {
      await _repository.deploy(
        repository: ticket.repository,
        workspaceId: workspaceId,
        projectId: projectId,
        itemId: ticket.itemId,
        response: response,
      );
      // Keep the local progress state until the Workshop refresh has replaced
      // the old deployable ticket with its durable dispatch receipt.
    } on Object catch (failure) {
      setError(failure);
      setBusyForObject(key, false);
      rethrow;
    }
  }

  void confirm(String itemId) {
    setBusyForObject(_busyKey(itemId), false);
  }

  Future<void> reset({
    required String workspaceId,
    required String projectId,
    required WorkshopTicket ticket,
  }) async {
    final key = _resetBusyKey(ticket.itemId);
    if (busy(key)) return;
    setError(null);
    setBusyForObject(key, true);
    try {
      await _repository.reset(
        repository: ticket.repository,
        workspaceId: workspaceId,
        projectId: projectId,
        itemId: ticket.itemId,
      );
      // The server receipt and Project status are authoritative. Keep the
      // action pending until a fresh board replaces the superseded state.
    } on Object catch (failure) {
      setError(failure);
      setBusyForObject(key, false);
      rethrow;
    }
  }

  void confirmReset(String itemId) {
    setBusyForObject(_resetBusyKey(itemId), false);
  }
}
