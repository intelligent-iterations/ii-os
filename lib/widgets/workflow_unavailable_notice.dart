import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

/// Explains why a generation surface has nothing runnable.
///
/// Replaces the byte-identical `_UnavailableWorkflow` and
/// `_UnavailableSongWorkflow` that had been forked into two screens. A reason
/// that starts with "waiting for" is a pending setup step rather than a
/// failure, so it renders as progress instead of a warning.
class WorkflowUnavailableNotice extends StatelessWidget {
  const WorkflowUnavailableNotice({
    required this.template,
    required this.fallbackReason,
    super.key,
  });

  final WorkflowTemplateModel? template;

  /// Shown when the template carries no reason of its own, e.g.
  /// 'No enabled image workflow is available.'
  final String fallbackReason;

  String get _reason {
    final reason = template?.disabledReason ?? '';
    return reason.isEmpty ? fallbackReason : reason;
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    if (reason.toLowerCase().startsWith('waiting for')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: IiOsSpacing.sm),
        child: WorkflowPendingNotice(message: reason),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.sm),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circleAlert,
            size: 17,
            color: IiOsColors.amber,
          ),
          IiOsGap.hXs,
          Expanded(
            child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
