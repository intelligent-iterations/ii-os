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

Future<OrganizationRunnerPoolDraft?> showOrganizationRunnerPoolDialog(
  BuildContext context,
) => showDialog<OrganizationRunnerPoolDraft>(
  context: context,
  builder: (context) => const _RunnerPoolDialog(),
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
