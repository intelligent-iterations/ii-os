import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

Widget buildIiOsErrorWidget(FlutterErrorDetails details) =>
    const IiOsUnexpectedErrorView();

class IiOsUnexpectedErrorView extends StatelessWidget {
  const IiOsUnexpectedErrorView({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    return ColoredBox(
      color: IiOsColors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: IiOsColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(IiOsSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    color: IiOsColors.red,
                    size: 32,
                  ),
                  IiOsGap.vSm,
                  Text(
                    'This screen could not be displayed',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  IiOsGap.vXs,
                  Text(
                    'The error was reported automatically. Return home and '
                    'try the action again.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  IiOsGap.vMd,
                  FilledButton.icon(
                    onPressed: router == null ? null : () => router.go('/'),
                    icon: const Icon(LucideIcons.house, size: 17),
                    label: const Text('Return home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
