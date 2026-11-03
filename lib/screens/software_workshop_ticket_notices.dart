part of 'software_workshop_ticket_widgets.dart';

class _ReadinessSummary extends StatelessWidget {
  const _ReadinessSummary({required this.readiness});

  final WorkshopTicketReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final color = readiness.ready ? IiOsColors.green : IiOsColors.amber;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  readiness.ready
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  color: color,
                  size: 19,
                ),
                IiOsGap.hXs,
                Expanded(
                  child: Text(
                    readiness.ready
                        ? 'Ready for your approval'
                        : '${readiness.passedCount}/${readiness.checks.length} readiness checks passed',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            for (final check in readiness.checks.where(
              (check) => !check.passed,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 27),
                child: Text(
                  check.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RetryFailureNotice extends StatelessWidget {
  const _RetryFailureNotice({required this.ticket});

  final WorkshopTicket ticket;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.redTint,
      border: Border.all(color: IiOsColors.red),
      borderRadius: BorderRadius.circular(IiOsRadii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.circleX, color: IiOsColors.red, size: 19),
          IiOsGap.hXs,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Retry failed',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  ticket.agentRunDetail.isEmpty
                      ? 'The agent stopped on a deterministic setup error and will not retry automatically.'
                      : ticket.agentRunDetail,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CompactFact extends StatelessWidget {
  const _CompactFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: IiOsColors.muted),
      IiOsGap.hXxs,
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
