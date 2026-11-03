import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/ii_os_tokens.dart';

typedef RepositoryConnectionInput = ({int installationId, String repository});

Future<RepositoryConnectionInput?> showRepositoryConnectionDialog(
  BuildContext context, {
  required int? installationId,
  required String? repository,
}) => showDialog<RepositoryConnectionInput>(
  context: context,
  builder: (context) => _RepositoryConnectionDialog(
    installationId: installationId,
    repository: repository,
  ),
);

int? parseGitHubInstallationId(String value) {
  final input = value.trim();
  final direct = int.tryParse(input);
  if (direct != null && direct > 0) return direct;
  final uri = Uri.tryParse(input);
  if (uri == null || uri.host != 'github.com') return null;
  for (final segment in uri.pathSegments.reversed) {
    final id = int.tryParse(segment);
    if (id != null && id > 0) return id;
  }
  return null;
}

final _repositoryPattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$',
);

class _RepositoryConnectionDialog extends StatefulWidget {
  const _RepositoryConnectionDialog({
    required this.installationId,
    required this.repository,
  });

  final int? installationId;
  final String? repository;

  @override
  State<_RepositoryConnectionDialog> createState() =>
      _RepositoryConnectionDialogState();
}

class _RepositoryConnectionDialogState
    extends State<_RepositoryConnectionDialog> {
  late final TextEditingController _installation;
  late final TextEditingController _repository;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _installation = TextEditingController(
      text: widget.installationId?.toString() ?? '',
    );
    _repository = TextEditingController(text: widget.repository ?? '');
  }

  @override
  void dispose() {
    _installation.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(LucideIcons.gitBranch),
    title: const Text('Connect a repository'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the legacy GitHub App installation and one selected repository. New workspaces select an organization-owned GitHub resource instead.',
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _installation,
              autofocus: widget.installationId == null,
              decoration: const InputDecoration(
                labelText: 'GitHub App installation link or ID',
                hintText: 'https://github.com/settings/installations/123456',
                prefixIcon: Icon(LucideIcons.gitFork, size: 18),
              ),
              validator: (value) =>
                  parseGitHubInstallationId(value ?? '') == null
                  ? 'Paste a GitHub installation link or positive ID.'
                  : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('github.com', '/settings/installations'),
                  webOnlyWindowName: '_blank',
                ),
                icon: const Icon(LucideIcons.externalLink, size: 15),
                label: const Text('Find my GitHub installations'),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _repository,
              decoration: const InputDecoration(
                labelText: 'Repository',
                hintText: 'owner/repository',
                prefixIcon: Icon(LucideIcons.gitBranch, size: 18),
              ),
              validator: (value) =>
                  _repositoryPattern.hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Use the GitHub owner/repository format.',
            ),
            IiOsGap.vSm,
            const Text(
              'After saving, the Firebase function requests a short-lived installation token and reads this repository directly. No workflow or runner starts.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, (
            installationId: parseGitHubInstallationId(_installation.text)!,
            repository: _repository.text.trim(),
          ));
        },
        child: const Text('Save and check connection'),
      ),
    ],
  );
}
