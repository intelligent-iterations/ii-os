import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'gallery_sections.dart';
import 'widgets/gallery_nav.dart';

/// Navigation plus the selected section.
///
/// Uses the package's own [IiOsBreakpoints.rail] threshold to choose between a
/// rail and a drawer, so the gallery exercises the same responsive decision the
/// product makes.
class GalleryShell extends StatefulWidget {
  const GalleryShell({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  State<GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<GalleryShell> {
  int _selected = 0;
  GalleryViewport _viewport = GalleryViewport.fill;

  void _select(int index) {
    setState(() => _selected = index);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= IiOsBreakpoints.rail;
    final section = gallerySections[_selected];
    final controls = _GalleryControls(
      mode: widget.mode,
      onModeChanged: widget.onModeChanged,
      viewport: _viewport,
      onViewportChanged: (value) => setState(() => _viewport = value),
    );

    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: const Text('ii-os design system'),
              backgroundColor: palette.surface,
              actions: [controls, IiOsGap.hXs],
            ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: GalleryNav(selected: _selected, onSelect: _select),
              ),
            ),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 260,
              child: Material(
                color: palette.surface,
                child: SafeArea(
                  child: GalleryNav(
                    selected: _selected,
                    onSelect: _select,
                    showTitle: true,
                  ),
                ),
              ),
            ),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      IiOsSpacing.md,
                      IiOsSpacing.sm,
                      IiOsSpacing.md,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: controls,
                    ),
                  ),
                Expanded(
                  child: _ViewportFrame(
                    viewport: _viewport,
                    child: (viewWidth) =>
                        _SectionView(section: section, width: viewWidth),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section, required this.width});

  final GallerySection section;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: iiOsPageGutter(width),
        vertical: IiOsSpacing.xl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(section.title, style: text.headlineMedium),
              IiOsGap.vXxs,
              Text(section.blurb, style: text.bodyLarge),
              IiOsGap.vXl,
              section.build(),
              IiOsGap.vXxl,
            ],
          ),
        ),
      ),
    );
  }
}

/// The widths the gallery can pretend to be.
///
/// A primitive is only proven at the sizes it has to survive, and the product's
/// own breakpoints read `MediaQuery`, so the frame overrides it rather than
/// merely narrowing the box -- otherwise a component would keep its desktop
/// layout inside a phone-width strip and prove nothing.
enum GalleryViewport {
  phone('Phone', 390),
  tablet('Tablet', 820),
  fill('Fill', null);

  const GalleryViewport(this.label, this.width);

  final String label;
  final double? width;
}

class _ViewportFrame extends StatelessWidget {
  const _ViewportFrame({required this.viewport, required this.child});

  final GalleryViewport viewport;
  final Widget Function(double width) child;

  @override
  Widget build(BuildContext context) {
    final target = viewport.width;
    if (target == null) {
      return LayoutBuilder(
        builder: (context, constraints) => child(constraints.maxWidth),
      );
    }
    final palette = IiOsPalette.of(context);
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: palette.neutralTint,
      child: Center(
        child: SizedBox(
          width: target,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvas,
              border: Border.symmetric(
                vertical: BorderSide(color: palette.border),
              ),
            ),
            child: MediaQuery(
              data: media.copyWith(size: Size(target, media.size.height)),
              child: child(target),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryControls extends StatelessWidget {
  const _GalleryControls({
    required this.mode,
    required this.onModeChanged,
    required this.viewport,
    required this.onViewportChanged,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;
  final GalleryViewport viewport;
  final ValueChanged<GalleryViewport> onViewportChanged;

  @override
  Widget build(BuildContext context) {
    final dark = mode == ThemeMode.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<GalleryViewport>(
          showSelectedIcon: false,
          segments: [
            for (final option in GalleryViewport.values)
              ButtonSegment(value: option, label: Text(option.label)),
          ],
          selected: {viewport},
          onSelectionChanged: (value) => onViewportChanged(value.first),
        ),
        IiOsGap.hSm,
        IconButton(
          tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
          onPressed: () =>
              onModeChanged(dark ? ThemeMode.light : ThemeMode.dark),
          icon: Icon(
            dark ? LucideIcons.sun : LucideIcons.moon,
            size: IiOsIconSize.md,
          ),
        ),
      ],
    );
  }
}
