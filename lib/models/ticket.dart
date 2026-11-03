import 'models.dart';

final class TicketModel {
  const TicketModel({
    required this.number,
    required this.title,
    required this.definitionOfDone,
    required this.howToTest,
    required this.permissionProfile,
    required this.permissionRef,
    required this.context,
    required this.state,
    required this.url,
    required this.updatedAt,
    required this.structured,
    required this.agentReady,
  });

  factory TicketModel.fromJson(JsonMap json) {
    final permissions = asJsonMap(json['permissions']);
    return TicketModel(
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      definitionOfDone: json['definitionOfDone'] as String? ?? '',
      howToTest: json['howToTest'] as String? ?? '',
      permissionProfile: permissions['profile'] as String? ?? 'none',
      permissionRef: permissions['ref'] as String? ?? 'dev',
      context: json['context'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: json['url'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      structured: json['structured'] as bool? ?? false,
      agentReady: asJsonMap(json['agent'])['ready'] as bool? ?? false,
    );
  }

  final int number;
  final String title;
  final String definitionOfDone;
  final String howToTest;
  final String permissionProfile;
  final String permissionRef;
  final String context;
  final String state;
  final String url;
  final DateTime? updatedAt;
  final bool structured;
  final bool agentReady;
}
