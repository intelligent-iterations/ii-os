import '../models/models.dart';
import '../services/api_client.dart';

/// Reads an organization's execution fleet, and manages the credentials its
/// publisher reports with.
abstract interface class FleetRepository {
  /// The fleet as last reported, or null when this organization has never
  /// connected one -- an ordinary state, not a failure.
  Future<FleetReport?> read(String organizationId);

  /// Issues a reporting credential. The cleartext is returned once and is not
  /// recoverable afterwards.
  Future<String> issueCredential({
    required String organizationId,
    required String label,
  });
}

final class FleetApiRepository implements FleetRepository {
  const FleetApiRepository(this.api);

  final ApiClient api;

  @override
  Future<FleetReport?> read(String organizationId) async {
    final response = await api.get('v1/organizations/$organizationId/fleet');
    return parseFleetReport(response);
  }

  @override
  Future<String> issueCredential({
    required String organizationId,
    required String label,
  }) async {
    final response = await api.post(
      'v1/organizations/$organizationId/fleet/keys',
      body: {'label': label},
    );
    return asJsonMap(response['data'])['key']?.toString() ?? '';
  }
}

/// Parses the fleet payload. Split out because the request needs a signed-in
/// session and cannot run in a unit test, while this is where the bugs live.
FleetReport? parseFleetReport(JsonMap response) {
  final fleet = response['fleet'];
  if (fleet == null) return null;
  return FleetReport.fromJson(asJsonMap(fleet));
}
