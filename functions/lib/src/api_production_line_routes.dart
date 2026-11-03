part of 'api.dart';

extension ProductionLineRoutes on IiOsApi {
  Future<Response> _productionLineRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    final lines = ProductionLineStore(store);

    if (path.length == 4 && request.method == 'GET') {
      final membership = await store.requireAccess(
        actor,
        workspaceId,
        Capability.linesRead,
      );
      final visible = await lines.listVisible(membership, workspaceId);
      return jsonResponse(200, {
        'productionLines': visible.map((line) => line.toJson()).toList(),
        'colorTokens': productionLineColorTokens.toList()..sort(),
        'iconTokens': productionLineIconTokens.toList()..sort(),
      }, requestId: requestId);
    }

    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.linesManage);
      final body = await readJsonObject(request);
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'production_line.create',
        targetType: 'production_line',
        targetId: workspaceId,
        execute: () async =>
            (await lines.create(actor, workspaceId, body)).toJson(),
      );
    }

    if (path.length == 5 && request.method == 'GET') {
      final membership = await store.requireAccess(
        actor,
        workspaceId,
        Capability.linesRead,
      );
      final line = await lines.requireVisible(membership, workspaceId, path[4]);
      return jsonResponse(200, {
        'productionLine': line.toJson(),
      }, requestId: requestId);
    }

    if (path.length == 5 && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.linesManage);
      final body = await readJsonObject(request);
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'production_line.update',
        targetType: 'production_line',
        targetId: path[4],
        execute: () async =>
            (await lines.update(workspaceId, path[4], body)).toJson(),
      );
    }

    if (path.length == 5 && request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.linesManage);
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'production_line.delete',
        targetType: 'production_line',
        targetId: path[4],
        execute: () async {
          await lines.delete(workspaceId, path[4]);
          return {'productionLineId': path[4]};
        },
      );
    }

    if (path.length == 6 && path[5] == 'members' && request.method == 'GET') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.linesMembersManage,
      );
      return jsonResponse(200, {
        'members': await lines.listMembers(workspaceId, path[4]),
      }, requestId: requestId);
    }

    if (path.length == 7 && path[5] == 'members' && request.method == 'PUT') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.linesMembersManage,
      );
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'production_line.member.grant',
        targetType: 'production_line_member',
        targetId: '${path[4]}_${path[6]}',
        // An Admin can already grant themselves any line, so the boundary that
        // actually holds is this record, not a filter. Keep it queryable.
        metadata: {
          'productionLineId': path[4],
          'targetUid': path[6],
          'selfGrant': actor.uid == path[6],
        },
        execute: () async {
          await lines.grantMember(actor, workspaceId, path[4], path[6]);
          return {'productionLineId': path[4], 'uid': path[6]};
        },
      );
    }

    if (path.length == 7 &&
        path[5] == 'members' &&
        request.method == 'DELETE') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.linesMembersManage,
      );
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'production_line.member.revoke',
        targetType: 'production_line_member',
        targetId: '${path[4]}_${path[6]}',
        metadata: {
          'productionLineId': path[4],
          'targetUid': path[6],
          'selfRevoke': actor.uid == path[6],
        },
        execute: () async {
          await lines.revokeMember(workspaceId, path[4], path[6]);
          return {'productionLineId': path[4], 'uid': path[6]};
        },
      );
    }

    throw const ApiError(404, 'not_found', 'Production line route not found.');
  }
}
