import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api_error.dart';
import 'organization_resources.dart';

List<OrganizationRunnerPool> discoverFleetRunnerPools(
  Map<String, Object?>? report,
) {
  final hosts = _currentHosts(report);
  final grouped = <String, List<Map<String, Object?>>>{};
  for (final host in hosts) {
    for (final pool in _strings(host['pools']).toSet()) {
      if (_poolId.hasMatch(pool)) {
        grouped.putIfAbsent(pool, () => []).add(host);
      }
    }
  }
  if (grouped.isEmpty) {
    throw const ApiError(
      409,
      'fleet_pool_unavailable',
      'Fleet has no current host with enforceable pool membership.',
    );
  }
  if (grouped.length > maxOrganizationRunnerPools) {
    throw const ApiError(
      409,
      'fleet_pool_limit',
      'Fleet reports more pools than the organization catalog can grant.',
    );
  }
  final pools = grouped.entries.map((entry) {
    final capabilities = entry.value
        .expand((host) => _strings(host['capabilities']))
        .toSet();
    if (capabilities.isEmpty) {
      throw ApiError(
        409,
        'fleet_pool_unavailable',
        'Fleet pool ${entry.key} has no reported capabilities.',
      );
    }
    return OrganizationRunnerPool(
      id: 'runner_fleet_${_digest(entry.key)}',
      name: 'Fleet · ${entry.key}',
      provider: 'fleet',
      providerPoolId: entry.key,
      capabilities: capabilities,
      maxCpu: entry.value.map((host) => _positive(host['maxCpu'])).reduce(_max),
      maxRamMiB: entry.value
          .map((host) => _positive(host['maxRamMb']))
          .reduce(_max),
      maxConcurrent: entry.value.length,
    );
  }).toList();
  pools.sort(
    (left, right) => left.providerPoolId.compareTo(right.providerPoolId),
  );
  return pools;
}

/// Converts the current organization-scoped Fleet attestation into a bounded
/// authorization envelope. It does not register, create, or modify any host.
OrganizationRunnerPool discoverFleetRunnerPool(Map<String, Object?>? report) {
  final pools = discoverFleetRunnerPools(report);
  if (pools.length != 1) {
    throw const ApiError(
      409,
      'fleet_pool_ambiguous',
      'Select an exact Fleet pool instead of aggregating several pools.',
    );
  }
  return pools.single;
}

List<Map<String, Object?>> _currentHosts(Map<String, Object?>? report) {
  if (report == null) {
    throw const ApiError(
      409,
      'fleet_not_connected',
      'Connect organization Fleet reporting before syncing runner capacity.',
    );
  }
  if (report['stale'] == true) {
    throw const ApiError(
      409,
      'fleet_stale',
      'Wait for a fresh Fleet report before syncing runner capacity.',
    );
  }
  final rawHosts = report['hosts'];
  if (rawHosts is! List<Object?>) {
    throw const ApiError(
      409,
      'fleet_report_invalid',
      'Fleet did not report usable host capacity.',
    );
  }
  final hosts = rawHosts
      .whereType<Map<Object?, Object?>>()
      .map((value) => value.cast<String, Object?>())
      .where(
        (host) =>
            host['drain'] != true &&
            const {'ok', 'degraded'}.contains(host['health']) &&
            _positive(host['maxCpu']) > 0 &&
            _positive(host['maxRamMb']) > 0,
      )
      .toList();
  if (hosts.isEmpty) {
    throw const ApiError(
      409,
      'fleet_capacity_unavailable',
      'Fleet has no current non-draining host with reported capacity.',
    );
  }
  return hosts;
}

Iterable<String> _strings(Object? value) => value is List<Object?>
    ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
    : const [];

int _positive(Object? value) => value is num && value > 0 ? value.toInt() : 0;

int _max(int left, int right) => left > right ? left : right;

String _digest(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 12);

final _poolId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
