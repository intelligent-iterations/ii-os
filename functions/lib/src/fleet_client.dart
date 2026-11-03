import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'domain.dart';
import 'fleet_template.dart';

final class FleetClient {
  FleetClient({
    required this.controlPlaneUrl,
    required this.sharedSecret,
    required String jobTemplatesJson,
    http.Client? httpClient,
  }) : catalog = FleetTemplateCatalog.parse(jobTemplatesJson),
       _http = httpClient ?? http.Client();

  final String controlPlaneUrl;
  final String sharedSecret;
  final FleetTemplateCatalog catalog;
  final http.Client _http;

  List<Map<String, Object?>> listTemplates() => catalog.publicTemplates();

  FleetBuiltJob build({
    required Workspace workspace,
    required String actorUid,
    required String requestId,
    required String kind,
    required Map<String, Object?> input,
  }) => catalog.build(
    workspace: workspace,
    actorUid: actorUid,
    requestId: requestId,
    kind: kind,
    input: input,
  );

  Future<Map<String, Object?>> submit({
    required Workspace workspace,
    required String actorUid,
    required String requestId,
    required String kind,
    required Map<String, Object?> input,
  }) async {
    final built = build(
      workspace: workspace,
      actorUid: actorUid,
      requestId: requestId,
      kind: kind,
      input: input,
    );
    return submitRequest(built.request, requestId: requestId);
  }

  Future<Map<String, Object?>> submitRequest(
    Map<String, Object?> jobRequest, {
    required String requestId,
  }) async {
    _requireControlConfigured();
    final jobId = jobRequest['job_id'];
    if (jobId is! String || jobId.isEmpty) {
      throw const ApiError(
        500,
        'fleet_request_invalid',
        'The queued Fleet request has no job ID.',
      );
    }
    Object? response;
    try {
      response = await _request(
        'POST',
        'jobs',
        requestId: requestId,
        body: jobRequest,
      );
    } on ApiError catch (error) {
      if (error.code != 'fleet_duplicate_job') rethrow;
      return _existingSubmission(jobId);
    }
    final data = _asMap(response);
    return {
      'jobId': data['job_id'],
      'leaseId': data['lease_id'],
      'status': data['state'] ?? 'requested',
      'submittedAt': jobRequest['submitted_at'],
    };
  }

  Future<int> cancelPending(String jobId) async {
    _requireControlConfigured();
    final response = _asMap(
      await _request(
        'POST',
        'jobs/${Uri.encodeComponent(jobId)}/cancel_pending',
        body: const {'detail': 'ii-os interactive session stopped'},
      ),
    );
    return (response['cancelled_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> listJobs(String workspaceId) async {
    _requireControlConfigured();
    final responses = await Future.wait<Object?>([
      _request('GET', 'jobs'),
      _request('GET', 'leases'),
    ]);
    final jobs = responses[0];
    final leases = responses[1];
    if (jobs is! List<Object?> || leases is! List<Object?>) {
      throw const ApiError(
        502,
        'fleet_response_invalid',
        'Fleet returned invalid job data.',
      );
    }
    final leasesByJob = <String, List<Map<String, Object?>>>{};
    for (final rawLease in leases.whereType<Map<String, Object?>>()) {
      final jobId = rawLease['job_id'];
      if (jobId is String) {
        leasesByJob.putIfAbsent(jobId, () => []).add(rawLease);
      }
    }
    final result = <Map<String, Object?>>[];
    for (final job in jobs.whereType<Map<String, Object?>>()) {
      final tags = _optionalMap(job['tags']);
      if (tags['workspace_id'] != workspaceId) continue;
      final jobId = job['job_id'] as String? ?? '';
      result.add(_normalizeJob(job, leasesByJob[jobId] ?? const []));
    }
    result.sort((left, right) {
      return (right['submittedAt'] as String? ?? '').compareTo(
        left['submittedAt'] as String? ?? '',
      );
    });
    return result.take(50).toList();
  }

  Future<Map<String, Object?>> jobDetail(
    String workspaceId,
    String jobId,
  ) async {
    _requireControlConfigured();
    final responses = await Future.wait<Object?>([
      _request('GET', 'jobs/${Uri.encodeComponent(jobId)}'),
      _request('GET', 'leases'),
      _request('GET', 'events'),
    ]);
    final job = _asMap(responses[0]);
    final tags = _optionalMap(job['tags']);
    if (tags['workspace_id'] != workspaceId) {
      throw const ApiError(404, 'job_not_found', 'Fleet job not found.');
    }
    final leases = responses[1] is List<Object?>
        ? (responses[1]! as List<Object?>)
              .whereType<Map<String, Object?>>()
              .where((lease) => lease['job_id'] == jobId)
              .toList()
        : <Map<String, Object?>>[];
    final events = responses[2] is List<Object?>
        ? (responses[2]! as List<Object?>)
              .whereType<Map<String, Object?>>()
              .where((event) => event['job_id'] == jobId)
              .map(_normalizeEvent)
              .toList()
        : <Map<String, Object?>>[];
    return {..._normalizeJob(job, leases), 'events': events};
  }

  Future<Map<String, Object?>> _existingSubmission(String jobId) async {
    final responses = await Future.wait<Object?>([
      _request('GET', 'jobs/${Uri.encodeComponent(jobId)}'),
      _request('GET', 'leases'),
    ]);
    final job = _asMap(responses[0]);
    final leases = responses[1] is List<Object?>
        ? (responses[1]! as List<Object?>)
              .whereType<Map<String, Object?>>()
              .where((lease) => lease['job_id'] == jobId)
              .toList()
        : <Map<String, Object?>>[];
    final normalized = _normalizeJob(job, leases);
    return {
      'jobId': jobId,
      'leaseId': normalized['leaseId'],
      'status': normalized['status'],
      'submittedAt': normalized['submittedAt'],
    };
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? requestId,
    Map<String, Object?>? body,
  }) async {
    final base = controlPlaneUrl.endsWith('/')
        ? controlPlaneUrl
        : '$controlPlaneUrl/';
    final request = http.Request(method, Uri.parse(base).resolve(path))
      ..headers.addAll({
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-iif-auth': sharedSecret,
        'x-iif-request-id': ?requestId,
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _optionalMap(decoded);
      final serverCode = error['error_code'] as String? ?? '';
      final message =
          error['message'] as String? ?? 'Fleet rejected the request.';
      final code = switch ((response.statusCode, serverCode)) {
        (409, 'ERR_DUPLICATE_JOB_ID') => 'fleet_duplicate_job',
        (404, 'ERR_JOB_NOT_FOUND') => 'fleet_job_not_found',
        _ => 'fleet_request_failed',
      };
      throw ApiError(502, code, message);
    }
    return decoded;
  }

  void _requireControlConfigured() {
    final uri = Uri.tryParse(controlPlaneUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        sharedSecret.isEmpty) {
      throw const ApiError(
        503,
        'fleet_not_configured',
        'Fleet integration is not configured for this process.',
      );
    }
  }
}

Map<String, Object?> _normalizeJob(
  Map<String, Object?> job,
  List<Map<String, Object?>> leases,
) {
  leases.sort((left, right) {
    return (right['assigned_at'] as String? ?? '').compareTo(
      left['assigned_at'] as String? ?? '',
    );
  });
  final lease = leases.isEmpty ? null : leases.first;
  final tags = _optionalMap(job['tags']);
  return {
    'jobId': job['job_id'],
    'kind': tags['ii_os_job_kind'],
    'templateVersion': tags['ii_os_template_version'],
    'profile': job['profile'],
    'image': job['image'],
    'submittedAt': job['submitted_at'],
    'submittedBy': job['submitted_by'],
    'status': lease?['state'] ?? 'requested',
    'leaseId': lease?['id'],
    'hostId': lease?['host_id'],
    'runtimeName': lease?['vm_name'],
    'failReason': lease?['fail_reason'],
    'failDetail': lease?['fail_detail'],
  };
}

Map<String, Object?> _normalizeEvent(Map<String, Object?> event) {
  final payload = _optionalMap(event['payload']);
  final detail = payload['detail']?.toString() ?? '';
  final artifacts = payload['artifacts'] is List<Object?>
      ? (payload['artifacts']! as List<Object?>)
            .whereType<Map<String, Object?>>()
            .map((value) => Map<String, Object?>.from(value))
            .toList()
      : <Map<String, Object?>>[];
  return {
    'at': event['ts'] ?? event['at'],
    'kind': event['kind'],
    'leaseId': event['lease_id'],
    'hostId': event['host_id'],
    if (detail.isNotEmpty)
      'detail': detail.substring(0, detail.length.clamp(0, 500)),
    if (payload['exit_code'] != null) 'exitCode': payload['exit_code'],
    if (payload['job_failed'] != null) 'jobFailed': payload['job_failed'],
    if (artifacts.isNotEmpty) 'artifacts': artifacts,
  };
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw const ApiError(
    502,
    'fleet_response_invalid',
    'Fleet returned invalid data.',
  );
}

Map<String, Object?> _optionalMap(Object? value) {
  return value is Map<String, Object?> ? value : <String, Object?>{};
}
