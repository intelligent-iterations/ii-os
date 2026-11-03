import 'models.dart';

final class CodexAuthSessionModel {
  const CodexAuthSessionModel({
    required this.id,
    required this.repository,
    required this.status,
    required this.verificationUrl,
    required this.userCode,
    required this.runUrl,
    required this.errorCode,
    required this.detail,
    required this.terminal,
  });

  factory CodexAuthSessionModel.fromJson(JsonMap json) => CodexAuthSessionModel(
    id: json['id'] as String? ?? '',
    repository: json['repository'] as String? ?? '',
    status: json['status'] as String? ?? 'dispatching',
    verificationUrl: json['verificationUrl'] as String? ?? '',
    userCode: json['userCode'] as String? ?? '',
    runUrl: json['runUrl'] as String? ?? '',
    errorCode: json['errorCode'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    terminal: json['terminal'] == true,
  );

  final String id;
  final String repository;
  final String status;
  final String verificationUrl;
  final String userCode;
  final String runUrl;
  final String errorCode;
  final String detail;
  final bool terminal;

  bool get waitingForUser =>
      status == 'waiting_for_user' &&
      verificationUrl.isNotEmpty &&
      userCode.isNotEmpty;
  bool get succeeded => status == 'succeeded';
}
