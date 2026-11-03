import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/client_error_reporter.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

/// `EmptyState` moved to the design system, which owns the loading, empty, and
/// error surfaces together. Re-exported here because twenty call sites already
/// reach it through this file.
export 'package:ii_os_design_system/ii_os_design_system.dart' show EmptyState;

/// The title block of a [PageFrame], with an optional identity glyph.
class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, this.subtitle, this.leading});

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, IiOsGap.hSm],
        // Flexible, not a bare Column: the title used to sit directly in the
        // Wrap and inherit its width, so on a narrow viewport a long title now
        // has to be allowed to shrink rather than overflow the row.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.headlineSmall),
              if (subtitle != null) ...[
                IiOsGap.vXxs,
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.actions = const [],
    this.stickyFooter,
    this.scrollController,
    this.leading,
  });

  final String title;
  final String? subtitle;

  /// Shown before the title, for a page that belongs to one identified thing.
  ///
  /// Together with the sidebar entry this is the only place a production line's
  /// colour and icon appear: identity marks where you are, it does not
  /// redecorate what you are looking at.
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;
  final Widget? stickyFooter;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 700 ? 16.0 : 24.0;
        final footer = stickyFooter;
        return Stack(
          children: [
            SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                padding,
                20,
                padding,
                footer == null ? 40 : 112,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _PageHeading(
                            title: title,
                            subtitle: subtitle,
                            leading: leading,
                          ),
                          if (actions.isNotEmpty)
                            Wrap(spacing: 8, runSpacing: 8, children: actions),
                        ],
                      ),
                      IiOsGap.vLg,
                      child,
                    ],
                  ),
                ),
              ),
            ),
            if (footer != null)
              Positioned(
                left: padding,
                right: padding,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: footer,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? statusColor(label);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.tintFor(resolved),
        borderRadius: BorderRadius.circular(IiOsRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IiOsSpacing.xs,
          vertical: IiOsSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The dot carries the state a second time, so the roughly one in
            // twelve people with a colour vision deficiency are not reading
            // hue alone across a table of otherwise identical pills.
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: resolved,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              label.replaceAll('_', ' '),
              style: TextStyle(
                color: resolved,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color statusColor(String status) {
  return switch (status.toLowerCase()) {
    'cleaned' ||
    'finished' ||
    'completed' ||
    'success' ||
    'succeeded' ||
    'done' ||
    'ready for qa' ||
    'open' ||
    'dev' => IiOsColors.green,
    'running' ||
    'runner_online' ||
    'queued' ||
    'dispatching' ||
    'dispatched' ||
    'requested' ||
    'in_progress' ||
    'in progress' ||
    'agent working' ||
    'queued for agent' ||
    'cancelling' ||
    'pending' ||
    'prod' => IiOsColors.blue,
    'failed' ||
    'qa failed' ||
    'qa failed refinement' ||
    'cleanup_failed' ||
    'closed' => IiOsColors.red,
    'cancelled' => IiOsColors.muted,
    _ => IiOsColors.amber,
  };
}

class WorkflowPendingNotice extends StatelessWidget {
  const WorkflowPendingNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      decoration: BoxDecoration(
        color: IiOsColors.blueTint,
        border: Border.all(color: IiOsColors.blue),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

void showFailure(BuildContext context, Object error) {
  if (error is! ApiFailure) {
    unawaited(
      ClientErrorReporter.reportGlobal(
        error,
        StackTrace.current,
        source: 'ui.action',
      ),
    );
  }
  final message = error.toString().replaceFirst('ApiFailure: ', '');
  // `IiOsColors.red` is a `static const`, so this used to paint the light
  // theme's red behind the dark theme's own content colour -- 3.13:1, on the
  // one surface that only appears when something has already gone wrong.
  final palette = IiOsPalette.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: palette.danger.container,
        content: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.danger.text),
        ),
      ),
    );
}
