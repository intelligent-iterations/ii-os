import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

/// A titled block within a gallery section.
class SpecPanel extends StatelessWidget {
  const SpecPanel({
    required this.title,
    required this.children,
    this.caption,
    super.key,
  });

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            if (caption != null) ...[
              IiOsGap.vXxs,
              Text(caption!, style: text.bodySmall),
            ],
            IiOsGap.vMd,
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One labelled specimen: the token's name and metadata on the left, the thing
/// itself on the right.
class SpecRow extends StatelessWidget {
  const SpecRow({
    required this.name,
    required this.detail,
    required this.child,
    super.key,
  });

  final String name;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.labelLarge),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
          IiOsGap.hMd,
          Expanded(child: child),
        ],
      ),
    );
  }
}
