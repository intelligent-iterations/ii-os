import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../widgets/common.dart';

/// The job listing table, kept separate so its metadata and click-through
/// contract can be verified independently of API refresh behavior.
class JobsTable extends StatelessWidget {
  const JobsTable({required this.jobs, required this.onSelectJob, super.key});

  final List<JsonMap> jobs;
  final ValueChanged<String>? onSelectJob;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ClipRRect(
        borderRadius: IiOsRadii.mdAll,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('WORK TYPE')),
              DataColumn(label: Text('WORKFLOW')),
              DataColumn(label: Text('JOB ID')),
              DataColumn(label: Text('REPOSITORY')),
              DataColumn(label: Text('GITHUB ACTIONS')),
              DataColumn(label: Text('ESTIMATED GPU TIME')),
              DataColumn(label: Text('SUBMITTED')),
              DataColumn(label: Text('')),
            ],
            rows: jobs.map((job) => _row(context, job)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, JsonMap job) {
    final jobId = job['jobId'] as String? ?? '';
    final kind = (job['kind'] as String? ?? 'job')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    final workflow = job['workflowName']?.toString().trim();
    final runtimeEstimate = RuntimeEstimateSnapshot.fromJob(
      job['runtimeEstimate'],
    );
    final onOpen = jobId.isEmpty ? null : () => onSelectJob?.call(jobId);
    return DataRow(
      onSelectChanged: onOpen == null ? null : (_) => onOpen(),
      cells: [
        DataCell(StatusPill(job['status'] as String? ?? 'requested')),
        DataCell(Text(jobWorkTypeLabel(job['workType']))),
        DataCell(Text(workflow == null || workflow.isEmpty ? kind : workflow)),
        DataCell(
          SizedBox(
            width: 300,
            child: Text(
              jobId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        DataCell(Text(job['repository'] as String? ?? '\u2014')),
        DataCell(GitHubActionsRunLink(url: job['githubUrl']?.toString())),
        DataCell(
          Text(
            runtimeEstimate == null
                ? '\u2014'
                : 'About ${runtimeEstimate.durationLabel}',
          ),
        ),
        DataCell(Text(_shortDate(job['submittedAt']))),
        DataCell(
          IconButton(
            tooltip: 'View job',
            onPressed: onOpen,
            icon: const Icon(LucideIcons.panelRightOpen, size: IiOsIconSize.md),
          ),
        ),
      ],
    );
  }
}

/// The canonical GitHub Actions run URL with distinct open and copy actions.
class GitHubActionsRunLink extends StatelessWidget {
  const GitHubActionsRunLink({required this.url, super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final uri = _githubActionsUri(url);
    if (uri == null) return const Text('\u2014');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Open GitHub Actions run',
          child: InkWell(
            onTap: () async {
              await launchUrl(uri, webOnlyWindowName: '_blank');
            },
            child: Text(
              uri.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: IiOsPalette.of(context).brand.text,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        IiOsGap.hXs,
        IconButton(
          tooltip: 'Copy GitHub Actions URL',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: uri.toString()));
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('GitHub Actions URL copied.')),
              );
            }
          },
          icon: const Icon(LucideIcons.copy, size: IiOsIconSize.md),
        ),
      ],
    );
  }
}

Uri? _githubActionsUri(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      !uri.pathSegments.contains('actions') ||
      !uri.pathSegments.contains('runs')) {
    return null;
  }
  return uri;
}

String jobWorkTypeLabel(Object? value) => switch (value?.toString()) {
  'content' => 'Content',
  'runtime' => 'Runtime',
  'asset' => 'Asset',
  'host' => 'Computer host',
  _ => 'Other',
};

String _shortDate(Object? raw) {
  final value = raw?.toString() ?? '';
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value.isEmpty ? '\u2014' : value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}
