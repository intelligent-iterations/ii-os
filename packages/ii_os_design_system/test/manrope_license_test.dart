import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The OFL requires its licence to travel with the bundled Manrope files. The
// Flutter tool copies each package's LICENSE into an app's NOTICES, splitting
// sections on a line of 80 hyphens and reading each section's first paragraph
// as the names it covers. Keeping the OFL as a named section of this package's
// LICENSE is what puts it on the licence page of every app built on the
// design system.
void main() {
  test('the package LICENSE carries the Manrope OFL as its own section', () {
    final sections = File(
      'LICENSE',
    ).readAsStringSync().split('\n${'-' * 80}\n');
    final named = {
      for (final section in sections)
        section.substring(0, section.indexOf('\n\n')): section.substring(
          section.indexOf('\n\n') + 2,
        ),
    };
    expect(named.keys, ['ii_os_design_system', 'Manrope']);
    expect(named['ii_os_design_system'], contains('Apache License'));
    expect(
      named['Manrope']!.trim(),
      File('fonts/Manrope-LICENSE.txt').readAsStringSync().trim(),
    );
  });
}
