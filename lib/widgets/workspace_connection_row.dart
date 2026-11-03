import 'package:flutter/material.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

/// One connected-resource row: what it is, what is connected, and how many.
///
/// The count sets in the brand face rather than a platform monospace stack --
/// The brand family ships tabular figures, so the column stays aligned
/// typeface mid-row.
class WorkspaceConnectionRow extends StatelessWidget {
  const WorkspaceConnectionRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$title, $value. $detail',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 19, color: IiOsColors.muted),
              IiOsGap.hSm,
              SizedBox(
                width: 112,
                child: Text(title, style: textTheme.titleMedium),
              ),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ),
              IiOsGap.hMd,
              Text(value, style: textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
