import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart' show IiOsPalette;

import '../theme/ii_os_tokens.dart';

class WorkshopTicketStateSummary extends StatelessWidget {
  const WorkshopTicketStateSummary({
    required this.icon,
    required this.title,
    required this.message,
    this.progress = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final info = IiOsPalette.of(context).info;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: info.container,
          border: Border.all(color: info.text.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(IiOsRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progress)
                SizedBox.square(
                  dimension: 19,
                  child: CircularProgressIndicator(
                    color: info.text,
                    strokeWidth: 2.2,
                  ),
                )
              else
                Icon(icon, color: info.text, size: 19),
              IiOsGap.hXs,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IiOsGap.vXxs,
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
