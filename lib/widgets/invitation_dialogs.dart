import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

Future<void> showInvitationAcceptanceDialog({
  required BuildContext context,
  required String signedInEmail,
  required Future<List<JsonMap>> Function() loadInvitations,
  required Future<void> Function(String invitationId) onAccept,
  Future<void> Function()? onSwitchAccount,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => InvitationAcceptanceDialog(
      signedInEmail: signedInEmail,
      loadInvitations: loadInvitations,
      onAccept: onAccept,
      onSwitchAccount: onSwitchAccount,
    ),
  );
}

class InvitationAcceptanceDialog extends StatefulWidget {
  const InvitationAcceptanceDialog({
    required this.signedInEmail,
    required this.loadInvitations,
    required this.onAccept,
    this.onSwitchAccount,
    super.key,
  });

  final String signedInEmail;
  final Future<List<JsonMap>> Function() loadInvitations;
  final Future<void> Function(String invitationId) onAccept;
  final Future<void> Function()? onSwitchAccount;

  @override
  State<InvitationAcceptanceDialog> createState() =>
      _InvitationAcceptanceDialogState();
}

class _InvitationAcceptanceDialogState
    extends State<InvitationAcceptanceDialog> {
  bool _loading = true;
  String? _acceptingId;
  List<JsonMap> _invitations = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _acceptingId != null;
    return AlertDialog(
      title: const Text('Your invitations'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Signed in as ${widget.signedInEmail}'),
            IiOsGap.vXxs,
            Text(
              'Invitations are matched to your verified sign-in email.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              IiOsGap.vMd,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    size: 18,
                    color: IiOsColors.red,
                  ),
                  IiOsGap.hXs,
                  Expanded(child: Text(_error!)),
                ],
              ),
            ],
            IiOsGap.vMd,
            _invitationList(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _invitationList(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_invitations.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No pending invitations for ${widget.signedInEmail}.'),
          if (widget.onSwitchAccount != null) ...[
            IiOsGap.vXs,
            TextButton.icon(
              key: const Key('switch-invitation-account'),
              onPressed: _acceptingId == null ? _switchAccount : null,
              icon: const Icon(LucideIcons.userRoundCog, size: 17),
              label: const Text('Use another account'),
            ),
          ],
        ],
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _invitations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final invitation = _invitations[index];
          final id = invitation['id'] as String? ?? '';
          final accepting = _acceptingId == id;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.building2, size: 19),
            title: Text(
              invitation['workspaceName'] as String? ?? 'Workspace',
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Role: ${invitation['roleLabel'] as String? ?? 'Member'}',
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.icon(
              key: Key('accept-invitation-$id'),
              onPressed: _acceptingId != null || id.isEmpty
                  ? null
                  : () => _accept(id),
              icon: accepting
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.userPlus, size: 16),
              label: const Text('Accept'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invitations = await widget.loadInvitations();
      if (mounted) setState(() => _invitations = invitations);
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String invitationId) async {
    if (_acceptingId != null) return;
    setState(() {
      _acceptingId = invitationId;
      _error = null;
    });
    try {
      await widget.onAccept(invitationId);
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  Future<void> _switchAccount() async {
    final switchAccount = widget.onSwitchAccount;
    if (switchAccount == null || _acceptingId != null) return;
    Navigator.pop(context);
    await switchAccount();
  }
}

class InvitationCreatedDialog extends StatelessWidget {
  const InvitationCreatedDialog({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitation ready'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleCheck,
              color: IiOsColors.green,
              size: 28,
            ),
            IiOsGap.vSm,
            Text(
              email,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            IiOsGap.vXs,
            const Text(
              'They can now sign in with this Google or verified email '
              'account and accept the invitation from ii-os. No link or '
              'code is needed.',
            ),
            IiOsGap.vXs,
            Text(
              'The invitation expires in 7 days.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
