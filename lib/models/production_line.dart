import 'models.dart';

/// A durable binding of one repository, one GitHub Project board, and one
/// agent permission scope, carrying the identity a team navigates by.
///
/// Before this existed the same three choices were re-made from dropdowns on
/// every visit and survived only in the URL query string, so there was nowhere
/// to hang a name, a colour, or who is allowed to operate it.
final class ProductionLineModel {
  const ProductionLineModel({
    required this.id,
    required this.name,
    required this.repository,
    required this.projectId,
    required this.permissionProfileId,
    required this.permissionRef,
    required this.colorToken,
    required this.iconToken,
  });

  factory ProductionLineModel.fromJson(JsonMap json) => ProductionLineModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    repository: json['repository'] as String? ?? '',
    projectId: json['projectId'] as String? ?? '',
    permissionProfileId: json['permissionProfileId'] as String? ?? '',
    permissionRef: json['permissionRef'] as String? ?? 'dev',
    colorToken: json['colorToken'] as String? ?? '',
    iconToken: json['iconToken'] as String? ?? '',
  );

  final String id;
  final String name;
  final String repository;
  final String projectId;
  final String permissionProfileId;
  final String permissionRef;

  /// Identity keys resolved by `IiOsIdentity` in the design system. Stored as
  /// keys, never as a hex or an icon name, so the palette stays a design
  /// decision rather than user data.
  final String colorToken;
  final String iconToken;

  JsonMap toJson() => {
    'name': name,
    'repository': repository,
    'projectId': projectId,
    'permissionProfileId': permissionProfileId,
    'permissionRef': permissionRef,
    'colorToken': colorToken,
    'iconToken': iconToken,
  };
}
