import '../models/models.dart';
import 'client_telemetry_sanitizer.dart';

typedef ClientBreadcrumbClock = DateTime Function();

final class ClientBreadcrumbs {
  ClientBreadcrumbs({
    this.capacity = 30,
    this.retention = const Duration(minutes: 10),
    ClientBreadcrumbClock? clock,
  }) : _clock = clock ?? DateTime.now {
    if (capacity < 1 || capacity > 50) {
      throw ArgumentError.value(capacity, 'capacity');
    }
    if (retention <= Duration.zero || retention > const Duration(minutes: 15)) {
      throw ArgumentError.value(retention, 'retention');
    }
  }

  static ClientBreadcrumbs? _global;
  static const _categories = {'navigation', 'api'};
  static final _namePattern = RegExp(r'^[a-z][a-z0-9._-]{0,79}$');

  final int capacity;
  final Duration retention;
  final ClientBreadcrumbClock _clock;
  final List<_ClientBreadcrumb> _entries = [];

  static ClientBreadcrumbs? get global => _global;

  static void install(ClientBreadcrumbs breadcrumbs) {
    _global = breadcrumbs;
  }

  static void recordGlobal({
    required String category,
    required String name,
    String? route,
    String? requestId,
    int? statusCode,
  }) {
    _global?.record(
      category: category,
      name: name,
      route: route,
      requestId: requestId,
      statusCode: statusCode,
    );
  }

  void record({
    required String category,
    required String name,
    String? route,
    String? requestId,
    int? statusCode,
  }) {
    if (!_categories.contains(category)) {
      throw ArgumentError.value(category, 'category');
    }
    if (!_namePattern.hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    if (statusCode != null && (statusCode < 100 || statusCode > 599)) {
      throw ArgumentError.value(statusCode, 'statusCode');
    }
    final now = _clock().toUtc();
    _removeExpired(now);
    final entry = _ClientBreadcrumb(
      occurredAt: now,
      category: category,
      name: name,
      route: route == null ? null : sanitizeClientTelemetryRoute(route),
      requestId: requestId == null
          ? null
          : boundClientTelemetry(requestId.trim(), 100),
      statusCode: statusCode,
    );
    if (_entries.lastOrNull?.sameEvent(entry) == true) return;
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
  }

  List<JsonMap> snapshot() {
    _removeExpired(_clock().toUtc());
    return [for (final entry in _entries) entry.toJson()];
  }

  void _removeExpired(DateTime now) {
    _entries.removeWhere(
      (entry) => now.difference(entry.occurredAt) > retention,
    );
  }
}

final class _ClientBreadcrumb {
  const _ClientBreadcrumb({
    required this.occurredAt,
    required this.category,
    required this.name,
    this.route,
    this.requestId,
    this.statusCode,
  });

  final DateTime occurredAt;
  final String category;
  final String name;
  final String? route;
  final String? requestId;
  final int? statusCode;

  bool sameEvent(_ClientBreadcrumb other) =>
      category == other.category &&
      name == other.name &&
      route == other.route &&
      requestId == other.requestId &&
      statusCode == other.statusCode;

  JsonMap toJson() => {
    'occurredAt': occurredAt.toIso8601String(),
    'category': category,
    'name': name,
    if (route?.isNotEmpty == true) 'route': route,
    if (requestId?.isNotEmpty == true) 'requestId': requestId,
    if (statusCode != null) 'statusCode': statusCode,
  };
}
