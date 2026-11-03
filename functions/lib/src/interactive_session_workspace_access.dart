import 'auth_service.dart';
import 'domain.dart';
import 'workspace_store.dart';

abstract interface class InteractiveSessionWorkspaceAccess {
  Future<({Membership membership, Workspace workspace})> require(
    AuthenticatedUser actor,
    String workspaceId,
    Capability capability,
  );

  Future<Membership?> membership(String workspaceId, String subject);
}

final class WorkspaceStoreInteractiveSessionAccess
    implements InteractiveSessionWorkspaceAccess {
  const WorkspaceStoreInteractiveSessionAccess(this.store);

  final WorkspaceStore store;

  @override
  Future<({Membership membership, Workspace workspace})> require(
    AuthenticatedUser actor,
    String workspaceId,
    Capability capability,
  ) => store.requireAccessContext(actor, workspaceId, capability);

  @override
  Future<Membership?> membership(String workspaceId, String subject) =>
      store.getMembership(workspaceId, subject);
}
