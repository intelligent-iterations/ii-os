# Design system gallery

Renders the whole ii-os design system against its own theme.

```bash
flutter run -d chrome
```

Six sections:

- **Palette** -- every colour with its role, hex, and contrast against both
  `surface` and `canvas`, computed live with WCAG 2.1 relative luminance. Badges
  turn red when a colour drops below the duty recorded for it.
- **Type** -- all fifteen `TextTheme` slots set in the brand face, each labelled
  with its real size, weight, tracking, and line height.
- **Scale** -- the 4pt spacing scale and the radius scale drawn at true size.
- **Breakpoints** -- every threshold evaluated against the current window, with
  a live readout of width, size class, and page gutter. Resize to watch it move.
- **Surfaces** -- loading, refreshing, empty, and error side by side, plus
  `KpiCard` and `ResponsiveFieldPair`.
- **Controls** -- Material buttons, inputs, selection, and tables as the theme
  dresses them.

The gallery consumes the package exactly the way ii-os does -- `IiOsTheme.light()`
and nothing else -- so anything that looks wrong here is wrong in the product.

Adding a primitive to the package means adding it to a section here. A primitive
nobody can see is a primitive nobody will reuse.
