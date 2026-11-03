import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../widgets/artifact_preview.dart';
import '../widgets/common.dart';

/// The bounded artifact list within a job detail page.
class JobArtifactsSection extends StatelessWidget {
  const JobArtifactsSection({
    required this.controller,
    required this.workspaceId,
    required this.jobId,
    required this.artifacts,
    super.key,
  });

  final AppController controller;
  final String workspaceId;
  final String jobId;
  final List<JsonMap> artifacts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: SectionTitle('Artifacts (${artifacts.length})'),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: artifacts.length,
            itemBuilder: (context, index) {
              final artifact = artifacts[index];
              final bytes = (artifact['size_bytes'] as num?)?.toInt();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.fileOutput, size: 18),
                title: Text(artifact['path']?.toString() ?? 'output'),
                subtitle: Text(
                  [
                    if (bytes != null) '$bytes bytes',
                    artifact['content_type']?.toString(),
                  ].whereType<String>().join(' · '),
                ),
                trailing: ArtifactPreviewAction(
                  load: () => controller.readVerifiedArtifact(
                    workspaceId: workspaceId,
                    jobId: jobId,
                    artifact: artifact,
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// The ordered lifecycle event list within a job detail page.
class JobEventsSection extends StatelessWidget {
  const JobEventsSection({required this.events, super.key});

  final List<JsonMap> events;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      itemCount: events.length,
      separatorBuilder: (context, index) => IiOsGap.vXs,
      itemBuilder: (context, index) {
        final event = events[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: statusColor(event['kind']?.toString() ?? ''),
                shape: BoxShape.circle,
              ),
            ),
            IiOsGap.hSm,
            SizedBox(
              width: 150,
              child: Text(
                event['kind']?.toString().replaceAll('_', ' ') ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                event['detail']?.toString() ?? _shortDate(event['at']),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}

String _shortDate(Object? raw) {
  final value = raw?.toString() ?? '';
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value.isEmpty ? '\u2014' : value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}
