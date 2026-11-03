import 'package:google_cloud_firestore/google_cloud_firestore.dart';

bool recordRetentionExpired(
  Map<String, Object?> record, {
  DateTime? now,
  int fallbackDays = 30,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  final explicit = _date(record['expiresAt']);
  if (explicit != null) return !explicit.isAfter(current);
  final created = _date(record['createdAt']);
  if (created == null) return true;
  return !created
      .add(Duration(days: fallbackDays.clamp(1, 30)))
      .isAfter(current);
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}
