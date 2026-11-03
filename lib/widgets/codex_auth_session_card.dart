import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/github_setup_readiness.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

class CodexAuthSessionCard extends StatelessWidget {
  const CodexAuthSessionCard({
    required this.session,
    required this.error,
    required this.onRetry,
    this.embedded = false,
    super.key,
  });

  final CodexAuthSessionModel? session;
  final String? error;
  final VoidCallback? onRetry;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final value = session;
    final success = value?.succeeded == true;
    final failed = value?.terminal == true && !success || error != null;
    final content = Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            success ? 'Codex live-verified' : 'Verify Codex with OpenAI',
            trailing: StatusPill(
              _statusLabel(value?.status ?? 'error'),
              color: success
                  ? IiOsColors.green
                  : failed
                  ? IiOsColors.red
                  : IiOsColors.blue,
            ),
          ),
          IiOsGap.vXs,
          if (value?.waitingForUser == true) ...[
            const Text(
              'Open the official OpenAI page and enter this one-time code. The code expires after 15 minutes.',
            ),
            const SizedBox(height: 14),
            SelectableText(
              value!.userCode,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            IiOsGap.vSm,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(value.verificationUrl),
                    webOnlyWindowName: '_blank',
                  ),
                  icon: const Icon(LucideIcons.externalLink, size: 17),
                  label: const Text('Open OpenAI sign-in'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: value.userCode)),
                  icon: const Icon(LucideIcons.copy, size: 17),
                  label: const Text('Copy code'),
                ),
              ],
            ),
          ] else if (success) ...[
            Text(
              'A real Codex request succeeded. The credential was written directly to ${value?.repository} as the CODEX_AUTH_JSON GitHub Actions secret.',
            ),
          ] else ...[
            Text(
              value?.detail.isNotEmpty == true
                  ? value!.detail
                  : error ??
                        'Waiting for the ephemeral Fleet runner to return an OpenAI challenge\u2026',
            ),
            if (value?.terminal == true && onRetry != null) ...[
              IiOsGap.vSm,
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.rotateCw, size: 17),
                  label: const Text('Start verification again'),
                ),
              ),
            ],
          ],
          if (value?.runUrl.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(value!.runUrl),
                  webOnlyWindowName: '_blank',
                ),
                icon: const Icon(LucideIcons.logs, size: 16),
                label: const Text('View verification workflow'),
              ),
            ),
          ],
        ],
      ),
    );
    if (embedded) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: success ? IiOsColors.greenTint : IiOsColors.blueTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: IiOsColors.border),
        ),
        child: content,
      );
    }
    return Card(
      color: success ? IiOsColors.greenTint : IiOsColors.blueTint,
      child: content,
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'dispatching' => 'Starting',
  'waiting_for_user' => 'Sign in required',
  'validating' => 'Validating',
  'writing_secret' => 'Saving',
  'awaiting_cleanup' => 'Proving cleanup',
  'succeeded' => 'Live verified',
  'expired' => 'Expired',
  'cancelled' => 'Cancelled',
  _ => 'Failed',
};
