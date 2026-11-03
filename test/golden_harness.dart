import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/theme/ii_os_tokens.dart';

/// Wraps a widget in the real ii-os theme at a fixed width, so a golden
/// captures the design system rather than the ambient Material defaults.
///
/// Golden tests are the visual half of the token rules: the token files say
/// what the system *is*, and these say what it *looks like*. An unintended
/// theme change shows up here as a diff instead of shipping.
Widget goldenHarness(Widget child, {double width = 360}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: IiOsTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Loads the bundled Manrope faces so goldens render in the brand typeface rather
/// than the test runner's placeholder font.
Future<void> loadIiOsFonts() async {
  final loader = FontLoader(iiOsFontFamily);
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(
      rootBundle.load('packages/ii_os_design_system/fonts/Manrope-$weight.ttf'),
    );
  }
  await loader.load();

  // Icons are half of what these surfaces say, and an unloaded icon font
  // rasterises as an empty box -- a shape difference no golden would ever
  // flag, because every golden had the same one.
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
  await icons.load();
}
