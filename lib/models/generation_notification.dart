import 'models.dart';

final class GenerationNotification {
  const GenerationNotification({
    required this.id,
    required this.workspaceId,
    required this.jobId,
    required this.mediaKind,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.createdAt,
    required this.readAt,
  });

  factory GenerationNotification.fromJson(JsonMap json) {
    return GenerationNotification(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      jobId: json['jobId'] as String? ?? '',
      mediaKind: json['mediaKind'] as String? ?? 'image',
      title: json['title'] as String? ?? 'Generation ready',
      body: json['body'] as String? ?? '',
      deepLink: notificationDeepLink(json['deepLink']?.toString()),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
    );
  }

  final String id;
  final String workspaceId;
  final String jobId;
  final String mediaKind;
  final String title;
  final String body;
  final String deepLink;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  GenerationNotification markRead(DateTime value) => GenerationNotification(
    id: id,
    workspaceId: workspaceId,
    jobId: jobId,
    mediaKind: mediaKind,
    title: title,
    body: body,
    deepLink: deepLink,
    createdAt: createdAt,
    readAt: value,
  );
}

String notificationDeepLink(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null) return '/';
  if (uri.hasScheme && uri.scheme != 'https') return '/';
  if (uri.hasScheme) {
    return Uri(
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
  return uri.path.startsWith('/') ? uri.toString() : '/';
}
