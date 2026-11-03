part of 'job_submission_result.dart';

final class _FailedJobRecovery extends StatelessWidget {
  const _FailedJobRecovery({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IiOsGap.vSm,
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
        ),
        if (onRetry != null || retrying) ...[
          IiOsGap.vSm,
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('failed-generation-retry'),
              onPressed: onRetry,
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 16),
              label: Text(
                retrying ? 'Retrying generation\u2026' : 'Retry generation',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

extension on _JobSubmissionResultState {
  bool _retryAvailable(bool failed) =>
      failed &&
      widget.onRetry != null &&
      widget.controller.can('jobs.trigger') &&
      !_retrying;

  String _failureMessage(bool artifactMissing, String? errorCode) {
    if (artifactMissing) {
      return 'Generation completed, but no ${_mediaNoun()} was attached. Retry the generation.';
    }
    final description = _mediaDescription();
    return errorCode == null
        ? 'Generation failed before $description was produced. Retry the generation.'
        : 'Generation failed before $description was produced ($errorCode). Retry the generation.';
  }
}
