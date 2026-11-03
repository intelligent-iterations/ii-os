part of 'agent_activation_store.dart';

extension AgentActivationResetStore on AgentActivationStore {
  Future<void> beginReset({
    required String workspaceId,
    required String projectItemId,
    required String resetRequestId,
    required AuthenticatedUser actor,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final activation = (await transaction.get(ref)).data();
      final dispatch = (await transaction.get(dispatchRef)).data();
      final now = DateTime.now().toUtc();
      requireAgentTicketResetAllowed(activation, dispatch, now);
      final timestamp = Timestamp.fromDate(now);
      final resetState = {
        'status': 'resetting',
        'resetRequestId': resetRequestId,
        'resetRequestedByUid': actor.uid,
        'resetRequestedAt': timestamp,
        'claimId': null,
        'claimExpiresAt': null,
        'updatedAt': timestamp,
      };
      transaction.set(ref, resetState, options: const SetOptions.merge());
      transaction.set(
        dispatchRef,
        resetState,
        options: const SetOptions.merge(),
      );
    });
  }

  Future<void> completeReset({
    required String workspaceId,
    required String projectItemId,
    required String resetRequestId,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final activation = (await transaction.get(ref)).data();
      if (activation?['status'] == 'reset' &&
          activation?['resetRequestId'] == resetRequestId) {
        return;
      }
      if (activation?['status'] != 'resetting' ||
          activation?['resetRequestId'] != resetRequestId) {
        throw const ApiError(
          409,
          'agent_ticket_reset_superseded',
          'A newer reset or deployment replaced this request. Refresh the ticket.',
        );
      }
      final timestamp = Timestamp.now();
      final resetState = {
        'status': 'reset',
        'resetCompletedAt': timestamp,
        'updatedAt': timestamp,
      };
      transaction.update(ref, resetState);
      transaction.set(
        dispatchRef,
        resetState,
        options: const SetOptions.merge(),
      );
    });
  }
}
