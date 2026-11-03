/// The ii-os colour palette, typography, and `ThemeData`.
///
/// These now live in `package:ii_os_design_system`. This file stays as the
/// app's import path so existing `import '../theme/ii_os_theme.dart';` lines
/// keep working, and so there is one obvious place to look for "where does the
/// theme come from".
///
/// The palette carries its accessibility duty with it: every colour in
/// `IiOsColors.all` records the WCAG ratio it owes for the job it does, and the
/// package's `contrast_test.dart` fails the build if an edit drops one below
/// it. `IiOsContrast` is exported too, so app-side code that composes a colour
/// can measure it rather than guess.
///
/// Change the palette or the theme in the package, not here.
library;

export 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        IiOsColors,
        IiOsContrast,
        IiOsHue,
        IiOsIdentity,
        IiOsIdentityGlyph,
        IiOsPalette,
        IiOsSwatch,
        IiOsTheme,
        IiOsTypography,
        iiOsFontFamily;
