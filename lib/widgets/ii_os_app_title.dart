import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../config/app_config.dart';

/// Product identity shown in the signed-in shell.
class IiOsAppTitle extends StatelessWidget {
  const IiOsAppTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const IiOsMark(size: 26),
      IiOsGap.hXs,
      Text(
        'ii-os',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      IiOsGap.hXs,
      Tooltip(
        message: AppConfig.buildDetails(),
        child: IiOsMetaChip(label: AppConfig.buildLabel()),
      ),
    ],
  );
}
