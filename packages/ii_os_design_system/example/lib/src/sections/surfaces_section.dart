import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/spec_panel.dart';

/// The loading / empty / error surfaces, side by side.
///
/// Seeing all three together is the point: a page has to have an answer for
/// each, and a refresh must never blank content that is already on screen --
/// that is what [RefreshingStrip] is for.
class SurfacesSection extends StatelessWidget {
  const SurfacesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpecPanel(
          title: 'Media well',
          caption:
              'The ground generated artwork sits on. Deep in both modes, so a '
              'thumbnail reads the same either way and a grid never flashes '
              'white between a spinner and a picture.',
          children: [
            SizedBox(
              height: 120,
              child: IiOsMediaWell(
                child: Icon(LucideIcons.play, color: Colors.white, size: 34),
              ),
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'State surfaces',
          caption:
              'Gate the first-load spinner on the data being empty, never on '
              'a busy flag alone. A background refresh that replaces content '
              'the operator is reading is a regression, not a loading state.',
          children: const [
            _Demo(
              name: 'LoadingSurface',
              note: 'First load, nothing to show yet',
              child: LoadingSurface(label: 'Loading characters'),
            ),
            _Demo(
              name: 'RefreshingStrip',
              note: 'A reload behind content already on screen',
              child: Align(
                alignment: Alignment.centerLeft,
                child: RefreshingStrip(),
              ),
            ),
            _Demo(
              name: 'EmptyState',
              note: 'Nothing here yet, with the action that changes that',
              child: EmptyState(
                title: 'No characters yet',
                message:
                    'Characters you create appear here with their sheets and '
                    'reference images.',
                icon: LucideIcons.users,
              ),
            ),
            _ErrorDemo(),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'PendingIcon',
          caption:
              'Forty-one files hand-rolled this, each choosing its own '
              'dimension, so buttons changed width when they went busy and '
              'rows jumped. Both states occupy the same square.',
          children: [
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () {},
                  icon: const PendingIcon(
                    icon: LucideIcons.send,
                    pending: false,
                  ),
                  label: const Text('Send'),
                ),
                IiOsGap.hSm,
                FilledButton.icon(
                  onPressed: () {},
                  icon: const PendingIcon(
                    icon: LucideIcons.send,
                    pending: true,
                    pendingLabel: 'Sending',
                  ),
                  label: const Text('Send'),
                ),
                IiOsGap.hSm,
                // Tinted, for a glyph that carries meaning the surrounding
                // theme does not. The spinner takes the same colour.
                const PendingIcon(
                  icon: LucideIcons.plus,
                  pending: false,
                  size: IiOsIconSize.xl,
                  color: IiOsColors.green,
                ),
                IiOsGap.hSm,
                const PendingIcon(
                  icon: LucideIcons.plus,
                  pending: true,
                  size: IiOsIconSize.xl,
                  color: IiOsColors.green,
                  pendingLabel: 'Creating',
                ),
              ],
            ),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'BackgroundWorkCard',
          caption:
              'Work that finishes minutes later and elsewhere usually gets a '
              'toast and then nothing, leaving the surface looking idle while '
              'it is busy. That invites a duplicate dispatch. Put this where '
              'the result will land. The stopped-watching state is amber, not '
              'red: it is not a failure, and must not claim to be. It still carries a '
              'way to start the work again, so it is never a dead end.',
          children: [
            BackgroundWorkCard(
              running: true,
              title: 'Installing agent permissions\u2026',
              detail:
                  'The installer is running in your repository. This normally '
                  'takes a few minutes \u2014 you can leave this page open.',
              onFollow: () {},
              followLabel: 'Watch the run',
            ),
            IiOsGap.vSm,
            BackgroundWorkCard(
              running: false,
              title: 'This is taking longer than usual',
              detail:
                  'It may still be waiting its turn to run, and it may still '
                  'finish on its own. Starting again is safe.',
              onFollow: () {},
              followLabel: 'Watch the run',
              onRetry: () {},
              retryLabel: 'Install again',
            ),
          ],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'PermissionChangeGuide',
          caption:
              'Exact settings to change in someone else\u2019s system, named '
              'the way that system names them. The reason line is not padding: '
              'widening access to your own code is a decision, and a row that '
              'says only "none -> Read and write" earns either a refusal or an '
              'approval nobody read.',
          children: [
            PermissionChangeGuide(
              steps: [
                'Open permission settings.',
                'Find each named permission and choose the value shown.',
                'Save, approve the update if asked, then return here.',
              ],
              changes: [
                PermissionChange(
                  name: 'Contents',
                  section: 'Repository permissions',
                  currentValue: 'No access',
                  requiredValue: 'Read-only',
                  reason:
                      'Lets the app read the rules you commit. It cannot write '
                      'your code \u2014 changes arrive as a pull request.',
                ),
                PermissionChange(
                  name: 'Issues',
                  section: 'Repository permissions',
                  currentValue: 'Read-only',
                  requiredValue: 'Read and write',
                  reason:
                      'Lets it post progress on the ticket you gave it. It can '
                      'never open new tickets.',
                ),
              ],
            ),
          ],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'ReviewedCommitGuide',
          caption:
              'A gate the product is deliberately unable to pass by itself \u2014 '
              'a human-review marker is worthless if the thing being '
              'authorised can mint it. The copyable command is the entire '
              'experience; without it the step is an unexplained wall, and a '
              'refresh button next to it is the cruellest possible offer.',
          children: [
            ReviewedCommitGuide(
              subject: 'acme-co/example-app on dev',
              marker: 'release-bootstrap-4f2a9c1',
              command:
                  'git tag release-bootstrap-4f2a9c1 4f2a9c1 && '
                  'git push origin release-bootstrap-4f2a9c1',
            ),
          ],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'InlineFormError',
          caption:
              'A rejected action reported next to the field that caused it, '
              'rather than in a snackbar that vanishes before it is read. '
              'Renders nothing when the message is null, so holding one in a '
              'layout costs no shift.',
          children: [
            InlineFormError(message: 'That sign-in code has expired.'),
            InlineFormError(message: null),
          ],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'IiOsMark',
          caption:
              'Drawn rather than shipped as an asset, so it stays crisp at '
              'every size and costs no image decode on first paint \u2014 it is the '
              'first thing rendered.',
          children: [_MarkRow()],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'KpiCard',
          caption:
              'Value and label merge into one semantic node so a screen '
              'reader announces "Active jobs, 4" rather than a bare number. An '
              'absent value is an em dash, which is not the same as zero.',
          children: [_KpiRow()],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'ResponsiveFieldPair',
          caption:
              'Two fields share a row above 560px and stack below it. Narrow '
              'the window to watch it fold.',
          children: [
            ResponsiveFieldPair(
              first: const TextField(
                decoration: InputDecoration(labelText: 'Width'),
              ),
              second: const TextField(
                decoration: InputDecoration(labelText: 'Height'),
              ),
            ),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'GenerationWorkspace',
          caption:
              'A generation form beside its live preview above 980px, and '
              'the same two panes stacked below it. Narrow the window to '
              'watch it fold.',
          children: [
            GenerationWorkspace(
              form: const Card(
                child: Padding(
                  padding: EdgeInsets.all(IiOsSpacing.lg),
                  child: TextField(
                    decoration: InputDecoration(labelText: 'Prompt'),
                    minLines: 3,
                    maxLines: 3,
                  ),
                ),
              ),
              preview: const GenerationSlot(
                phase: GenerationPhase.idle,
                idleHint: 'Your image will appear here',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MarkRow extends StatelessWidget {
  const _MarkRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final size in [24.0, 40.0, 64.0]) ...[
          IiOsMark(size: size, semanticLabel: 'ii-os at $size'),
          IiOsGap.hMd,
        ],
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow();

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: KpiCard(
            label: 'Active jobs',
            value: '4',
            hue: palette.brand,
            caption: 'running',
            emphasised: true,
          ),
        ),
        IiOsGap.hMd,
        Expanded(
          child: KpiCard(
            label: 'Characters',
            value: '18',
            hue: palette.info,
            caption: '+3',
          ),
        ),
        IiOsGap.hMd,
        Expanded(
          child: KpiCard(
            label: 'Spend this month',
            value: null,
            hue: palette.accent,
            emptyNote: 'not measured yet',
          ),
        ),
      ],
    );
  }
}

class _ErrorDemo extends StatelessWidget {
  const _ErrorDemo();

  @override
  Widget build(BuildContext context) {
    return _Demo(
      name: 'ErrorSurface',
      note: 'Failed load, with recovery in the same place',
      child: ErrorSurface(
        title: 'Could not load characters',
        message: 'The workspace API did not answer. Nothing was changed.',
        onRetry: () {},
        secondaryActions: [
          OutlinedButton(
            onPressed: null,
            child: const Text('Create support ticket'),
          ),
        ],
        disabledReason: 'Ask a workspace editor to create a support ticket.',
      ),
    );
  }
}

class _Demo extends StatelessWidget {
  const _Demo({required this.name, required this.note, required this.child});

  final String name;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: text.labelLarge),
          Text(note, style: text.bodySmall),
          IiOsGap.vXs,
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: IiOsColors.canvas,
              borderRadius: IiOsRadii.mdAll,
              border: Border.all(color: IiOsColors.border),
            ),
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}
