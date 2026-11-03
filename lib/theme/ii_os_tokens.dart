/// Design tokens for ii-os.
///
/// The tokens themselves now live in `package:ii_os_design_system`, which owns
/// the scales, the theme, and the primitive surfaces, and renders all of them
/// in its own `example/` gallery. This file stays as the app's import path so
/// the eighty-odd screens and widgets that already say
/// `import '../theme/ii_os_tokens.dart';` keep working unchanged, and so rule 6
/// keeps a `lib/theme/` to exempt.
///
/// Rule 6 in `docs/ii-os-frontend.md` § Rules: outside
/// `lib/theme/`, spacing, gaps, radii, and breakpoints come from here and text
/// comes from `Theme.of(context).textTheme`. A raw numeric literal in a screen
/// or widget is a violation, because it is a design decision made in a place no
/// one will find it again.
///
/// Add a token in the package, not here.
library;

export 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        IiOsBreakpoints,
        IiOsGap,
        IiOsPreset,
        IiOsPresetScale,
        IiOsRadii,
        IiOsSpacing,
        iiOsPageGutter;
