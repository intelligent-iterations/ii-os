import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// One shape an image can come out as.
@immutable
final class IiOsAspectOption {
  const IiOsAspectOption({
    required this.label,
    required this.width,
    required this.height,
  });

  /// What the workflow is sent, and what the person reads: `16:9`.
  final String label;

  final double width;
  final double height;

  double get ratio => width / height;
}

/// The output shape, drawn at the shape it produces.
///
/// A dropdown of `1:1`, `4:3`, `3:4` asks the reader to do the arithmetic and
/// then imagine the result, and the two portrait entries look nearly identical
/// in a list. Rectangles do not need reading: the row shows what each choice
/// will hand back, and picking is recognition rather than translation.
class IiOsAspectChoice extends StatelessWidget {
  const IiOsAspectChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final List<IiOsAspectOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.xs,
      runSpacing: IiOsSpacing.xs,
      children: [
        for (final option in options)
          _AspectTile(
            option: option,
            selected: option.label == selected,
            onSelected: enabled ? () => onSelected(option.label) : null,
          ),
      ],
    );
  }
}

class _AspectTile extends StatelessWidget {
  const _AspectTile({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final IiOsAspectOption option;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final available = onSelected != null;
    final tint = selected
        ? palette.brand.text
        : (available ? palette.borderStrong : palette.border);
    // Both sides are scaled down from the same box, so a portrait and a
    // landscape choice take the same room and the row stays a row.
    final ratio = option.ratio;
    final width = ratio >= 1 ? _shapeBox : _shapeBox * ratio;
    final height = ratio >= 1 ? _shapeBox / ratio : _shapeBox;
    return Semantics(
      key: ValueKey('aspect-${option.label}'),
      container: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: available,
      label: option.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelected,
          borderRadius: IiOsRadii.mdAll,
          child: AnimatedContainer(
            duration: IiOsMotion.of(context, IiOsMotion.quick),
            curve: IiOsMotion.standard,
            width: _tileWidth,
            padding: const EdgeInsets.symmetric(
              vertical: IiOsSpacing.xs,
              horizontal: IiOsSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.brand.container : palette.surface,
              borderRadius: IiOsRadii.mdAll,
              border: Border.all(
                color: selected ? palette.brand.text : palette.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: _shapeFrame,
                  child: Center(
                    child: AnimatedContainer(
                      key: ValueKey('aspect-shape-${option.label}'),
                      duration: IiOsMotion.of(context, IiOsMotion.quick),
                      curve: IiOsMotion.standard,
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        color: selected ? palette.brand.fill : palette.canvas,
                        borderRadius: IiOsRadii.smAll,
                        border: Border.all(color: tint),
                      ),
                    ),
                  ),
                ),
                IiOsGap.vXxs,
                ExcludeSemantics(
                  child: Text(
                    option.label,
                    style: text.bodySmall?.copyWith(
                      color: selected ? palette.brand.text : palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The square the rectangle is drawn inside, so a portrait and a landscape
/// choice occupy the same room and the row stays a row.
const _shapeFrame = IiOsSpacing.xxl + IiOsSpacing.xs;

/// The longest side of the rectangle itself.
const _shapeBox = _shapeFrame - IiOsSpacing.xxs;

/// Wide enough for the tallest label and for a 44px tap target.
const _tileWidth = 64.0;
