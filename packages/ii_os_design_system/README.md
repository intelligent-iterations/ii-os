# ii_os_design_system

Design tokens, the ii-os `ThemeData`, and the primitive surfaces every page is
assembled from. Not published to pub.dev; consumed by path.

## Using it

```dart
import 'package:ii_os_design_system/ii_os_design_system.dart';

MaterialApp(
  theme: IiOsTheme.light(),
  home: const OperatorShell(),
);
```

Then measure everything from a token:

```dart
Padding(
  padding: const EdgeInsets.all(IiOsSpacing.md),   // not 16
  child: Column(children: [header, IiOsGap.vSm, body]),
)
```

The brand typeface ships with the package, so a consumer inherits Manrope by
depending on it -- no font declaration of its own required.

## What is in here

| | |
| --- | --- |
| `IiOsSpacing`, `IiOsGap` | 4pt scale, plus `const` gaps for rows and columns |
| `IiOsRadii` | 4 / 6 / 10 / 14 / pill, with ready-made `BorderRadius` |
| `IiOsBreakpoints` | Material window classes plus the app's own thresholds |
| `IiOsColors` | The palette, each entry carrying its WCAG duty |
| `IiOsTypography` | All fifteen `TextTheme` slots |
| `IiOsTheme.light()` | Cards, inputs, buttons, dividers, tables |
| `IiOsContrast` | WCAG 2.1 ratio maths, used by the tests and the gallery |
| `LoadingSurface`, `EmptyState`, `ErrorSurface`, `RefreshingStrip` | The state surfaces |
| `KpiCard`, `ResponsiveFieldPair` | Shared layout primitives |

## The gallery

```bash
cd example && flutter run -d chrome
```

Six sections -- palette, type, scale, breakpoints, surfaces, controls. The
palette measures each colour against both surfaces live rather than restating a
number from a comment, and the breakpoint readout updates as you resize the
window.

## Accessibility

`IiOsColors.all` records the contrast ratio each colour must clear for the job
it does. `test/contrast_test.dart` asserts it against both `surface` and
`canvas`, so editing a colour below its duty fails the build. That is why
`borderStrong` exists separately from `border`: interactive edges owe 3:1 under
WCAG 1.4.11, and the decorative hairline is 1.48:1.
