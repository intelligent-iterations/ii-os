import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/spacing.dart';

/// Two form fields that sit side by side when there is room and stack when
/// there is not.
///
/// Every generation surface hand-rolled this `LayoutBuilder` with its own
/// threshold. The shared threshold is [IiOsBreakpoints.pairedFields].
class ResponsiveFieldPair extends StatelessWidget {
  const ResponsiveFieldPair({
    required this.first,
    required this.second,
    super.key,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < IiOsBreakpoints.pairedFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, IiOsGap.vSm, second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            IiOsGap.hSm,
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
