import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/models.dart';

part 'organization_gcp_resource_dialog.dart';
part 'organization_runner_pool_dialog.dart';

Future<OrganizationGcpResourceDraft?> showOrganizationGcpResourceDialog(
  BuildContext context, {
  required String organizationId,
}) => showDialog<OrganizationGcpResourceDraft>(
  context: context,
  builder: (context) => _GcpResourceDialog(organizationId: organizationId),
);

/// Asks for runners the organization runs itself. Pass [existing] to edit a
/// pool kept by hand; the dialog never edits a pool from a capacity report.
Future<CustomerRunnerPoolInput?> showOrganizationRunnerPoolDialog(
  BuildContext context, {
  OrganizationRunnerPoolModel? existing,
}) => showDialog<CustomerRunnerPoolInput>(
  context: context,
  builder: (context) => _RunnerPoolDialog(existing: existing),
);

final _resourceId = RegExp(r'^[a-z][a-z0-9_]{2,63}$');
String? _idValidator(String? value) => _resourceId.hasMatch(value?.trim() ?? '')
    ? null
    : 'Use lowercase letters, numbers, and underscores.';

String? _nameValidator(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty || text.length > 400 ? 'This field is required.' : null;
}

String? _positiveIdValidator(String? value) =>
    (int.tryParse(value?.trim() ?? '') ?? 0) > 0
    ? null
    : 'Enter a positive number.';

// These mirror the server's runner pool checks so a person learns about a
// value before saving, not from a refusal afterwards.
final _runnerGroup = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _capability = RegExp(r'^[a-z0-9][a-z0-9._-]{1,99}$');

String? _runnerNameValidator(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty || text.length > 100
      ? 'Enter a name of up to 100 characters.'
      : null;
}

String? _runnerGroupValidator(String? value) =>
    _runnerGroup.hasMatch(value?.trim() ?? '')
    ? null
    : 'Use letters, digits, dots, dashes, or underscores, with no spaces.';

String? _capabilitiesValidator(String? value) {
  final capabilities = parseRunnerCapabilities(value ?? '');
  return capabilities.isNotEmpty && capabilities.every(_capability.hasMatch)
      ? null
      : 'Separate capabilities with commas. Each uses letters, digits, dots, '
            'dashes, or underscores.';
}
