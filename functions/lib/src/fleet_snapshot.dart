import 'api_error.dart';

/// Bounds on an inbound fleet report.
///
/// A publisher runs on the tenant's hardware and is therefore untrusted input,
/// not a trusted peer. Every list is capped and every string is truncated here
/// rather than at the database, so one misconfigured reporter cannot push a
/// document past Firestore's limit and take the page down for everyone in the
/// organization.
abstract final class FleetBounds {
  static const maxHosts = 200;
  static const maxActivity = 100;
  static const maxCapabilities = 64;
  static const maxRunnerKinds = 8;
  static const maxPools = 32;
  static const maxIdLength = 128;
  static const maxJobIdLength = 256;
  static const maxLabelLength = 64;

  /// A report older than this is shown as stale rather than as truth.
  static const freshness = Duration(minutes: 2);
}

/// One machine, as its fleet reported it.
final class FleetHostReport {
  const FleetHostReport({
    required this.id,
    required this.health,
    required this.drain,
    required this.capabilities,
    required this.runnerKinds,
    this.pools = const [],
    this.os,
    this.hardwareModel,
    this.lastHeartbeat,
    this.maxRamMb,
    this.freeRamMb,
    this.maxCpu,
    this.freeCpu,
    this.cpuCount,
    this.physicalRamMb,
    this.activeRuntimes,
    this.loadPerCpu,
    this.diskUsedPct,
    this.processCount,
  });

  final String id;

  /// `ok`, `unhealthy`, or `unknown`. Normalized on the way in so the UI never
  /// branches on a value a reporter invented.
  final String health;
  final bool drain;
  final List<String> capabilities;
  final List<String> runnerKinds;
  final List<String> pools;
  final String? os;
  final String? hardwareModel;
  final DateTime? lastHeartbeat;
  final int? maxRamMb;
  final int? freeRamMb;
  final int? maxCpu;
  final int? freeCpu;
  final int? cpuCount;
  final int? physicalRamMb;
  final int? activeRuntimes;
  final double? loadPerCpu;
  final double? diskUsedPct;
  final int? processCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'health': health,
    'drain': drain,
    'capabilities': capabilities,
    'runnerKinds': runnerKinds,
    'pools': pools,
    'os': os,
    'hardwareModel': hardwareModel,
    'lastHeartbeat': lastHeartbeat?.toIso8601String(),
    'maxRamMb': maxRamMb,
    'freeRamMb': freeRamMb,
    'maxCpu': maxCpu,
    'freeCpu': freeCpu,
    'cpuCount': cpuCount,
    'physicalRamMb': physicalRamMb,
    'activeRuntimes': activeRuntimes,
    'loadPerCpu': loadPerCpu,
    'diskUsedPct': diskUsedPct,
    'processCount': processCount,
  };

  static FleetHostReport fromJson(Map<String, Object?> json) => FleetHostReport(
    id: _requiredId(json['id'], 'host id'),
    health: _health(json['health']),
    drain: json['drain'] == true,
    capabilities: _stringList(
      json['capabilities'],
      FleetBounds.maxCapabilities,
    ),
    runnerKinds: _stringList(json['runnerKinds'], FleetBounds.maxRunnerKinds),
    pools: _stringList(json['pools'], FleetBounds.maxPools),
    os: _label(json['os']),
    hardwareModel: _label(json['hardwareModel']),
    lastHeartbeat: _time(json['lastHeartbeat']),
    maxRamMb: _nonNegativeInt(json['maxRamMb']),
    freeRamMb: _nonNegativeInt(json['freeRamMb']),
    maxCpu: _nonNegativeInt(json['maxCpu']),
    freeCpu: _nonNegativeInt(json['freeCpu']),
    cpuCount: _nonNegativeInt(json['cpuCount']),
    physicalRamMb: _nonNegativeInt(json['physicalRamMb']),
    activeRuntimes: _nonNegativeInt(json['activeRuntimes']),
    loadPerCpu: _nonNegativeDouble(json['loadPerCpu']),
    diskUsedPct: _nonNegativeDouble(json['diskUsedPct']),
    processCount: _nonNegativeInt(json['processCount']),
  );
}

/// One unit of work the fleet placed on a machine.
final class FleetActivityReport {
  const FleetActivityReport({
    required this.leaseId,
    required this.hostId,
    required this.jobId,
    required this.state,
    this.startedAt,
    this.updatedAt,
    this.reservedRamMb,
    this.failReason,
  });

  final String leaseId;
  final String hostId;
  final String jobId;
  final String state;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final int? reservedRamMb;
  final String? failReason;

  Map<String, Object?> toJson() => {
    'leaseId': leaseId,
    'hostId': hostId,
    'jobId': jobId,
    'state': state,
    'startedAt': startedAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'reservedRamMb': reservedRamMb,
    'failReason': failReason,
  };

  static FleetActivityReport fromJson(Map<String, Object?> json) =>
      FleetActivityReport(
        leaseId: _requiredId(json['leaseId'], 'lease id'),
        hostId: _requiredId(json['hostId'], 'host id'),
        jobId: _truncate(
          '${json['jobId'] ?? ''}'.trim(),
          FleetBounds.maxJobIdLength,
        ),
        state: _label(json['state']) ?? 'unknown',
        startedAt: _time(json['startedAt']),
        updatedAt: _time(json['updatedAt']),
        reservedRamMb: _nonNegativeInt(json['reservedRamMb']),
        failReason: _label(json['failReason']),
      );
}

/// One report of an organization's execution fleet at one moment.
final class FleetSnapshot {
  const FleetSnapshot({
    required this.observedAt,
    required this.hosts,
    required this.activity,
    this.controlPlaneId,
  });

  final DateTime observedAt;
  final List<FleetHostReport> hosts;
  final List<FleetActivityReport> activity;
  final String? controlPlaneId;

  Map<String, Object?> toJson() => {
    'observedAt': observedAt.toIso8601String(),
    'controlPlaneId': controlPlaneId,
    'hosts': hosts.map((host) => host.toJson()).toList(),
    'activity': activity.map((entry) => entry.toJson()).toList(),
  };

  /// Parses a publisher's report, rejecting anything past the bounds above.
  static FleetSnapshot fromJson(Map<String, Object?> json) {
    final hosts = _list(json['hosts']);
    final activity = _list(json['activity']);
    if (hosts.length > FleetBounds.maxHosts) {
      throw ApiError(
        413,
        'fleet_snapshot_too_large',
        'A fleet report may describe at most ${FleetBounds.maxHosts} machines.',
      );
    }
    if (activity.length > FleetBounds.maxActivity) {
      throw ApiError(
        413,
        'fleet_snapshot_too_large',
        'A fleet report may carry at most ${FleetBounds.maxActivity} activity entries.',
      );
    }
    final observedAt = _time(json['observedAt']);
    if (observedAt == null) {
      throw const ApiError(
        400,
        'invalid_fleet_snapshot',
        'A fleet report must carry an observedAt timestamp.',
      );
    }
    final parsedHosts = hosts.map(FleetHostReport.fromJson).toList();
    final seen = <String>{};
    for (final host in parsedHosts) {
      if (!seen.add(host.id)) {
        throw ApiError(
          400,
          'invalid_fleet_snapshot',
          'A fleet report named the machine ${host.id} twice.',
        );
      }
    }
    return FleetSnapshot(
      observedAt: observedAt,
      controlPlaneId: _label(json['controlPlaneId']),
      hosts: parsedHosts,
      activity: activity.map(FleetActivityReport.fromJson).toList(),
    );
  }
}

List<Map<String, Object?>> _list(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const ApiError(
      400,
      'invalid_fleet_snapshot',
      'A fleet report field that must be a list was not one.',
    );
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((entry) => entry.cast<String, Object?>())
      .toList();
}

String _requiredId(Object? value, String what) {
  final id = '${value ?? ''}'.trim();
  if (id.isEmpty || id.length > FleetBounds.maxIdLength) {
    throw ApiError(
      400,
      'invalid_fleet_snapshot',
      'A fleet report carried an unusable $what.',
    );
  }
  return id;
}

/// Normalizes to the three values the UI knows how to render.
String _health(Object? value) =>
    switch ('${value ?? ''}'.trim().toLowerCase()) {
      'ok' || 'healthy' => 'ok',
      // Fleet's own third value. A degraded machine is still reporting, so
      // collapsing it into unhealthy would show a machine that is talking to
      // us as one that has gone silent.
      'degraded' => 'degraded',
      'unhealthy' || 'unreachable' => 'unhealthy',
      _ => 'unknown',
    };

List<String> _stringList(Object? value, int limit) {
  if (value is! List) return const [];
  return value
      .map((entry) => _truncate('$entry'.trim(), FleetBounds.maxLabelLength))
      .where((entry) => entry.isNotEmpty)
      .take(limit)
      .toList();
}

String? _label(Object? value) {
  if (value == null) return null;
  final text = _truncate('$value'.trim(), FleetBounds.maxLabelLength);
  return text.isEmpty ? null : text;
}

String _truncate(String value, int limit) =>
    value.length <= limit ? value : value.substring(0, limit);

DateTime? _time(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

double? _nonNegativeDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || parsed.isNaN || parsed < 0) return null;
  return parsed;
}
