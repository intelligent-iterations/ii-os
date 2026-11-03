import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'character_design_regions.dart';

part 'character_silhouette_painters.dart';

class CharacterSilhouette extends StatelessWidget {
  const CharacterSilhouette({
    required this.kind,
    required this.regions,
    required this.selectedRegionId,
    required this.completion,
    required this.onRegionSelected,
    super.key,
  });

  final CharacterDesignKind kind;
  final List<CharacterDesignRegion> regions;
  final String selectedRegionId;
  final Map<String, double> completion;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    final hotspots = kind == CharacterDesignKind.head
        ? const {
            'hair': Alignment(0, -0.9),
            'eyes': Alignment(-0.67, -0.28),
            'nose': Alignment(0.56, -0.02),
            'mouth': Alignment(0.55, 0.38),
            'face': Alignment(-0.66, 0.43),
            'headClothing': Alignment(0.55, 0.86),
          }
        : const {
            'silhouette': Alignment(-0.68, -0.88),
            'upperBody': Alignment(0.62, -0.42),
            'armsHands': Alignment(-0.75, -0.12),
            'hips': Alignment(0.62, 0.04),
            'legsFeet': Alignment(-0.62, 0.68),
            'outfit': Alignment(0.65, 0.62),
          };
    final byId = {for (final region in regions) region.id: region};
    return Semantics(
      label: kind == CharacterDesignKind.head
          ? 'Interactive head silhouette'
          : 'Interactive body silhouette',
      child: Container(
        constraints: BoxConstraints(
          minHeight: kind == CharacterDesignKind.head ? 330 : 430,
        ),
        decoration: BoxDecoration(
          color: IiOsColors.canvas,
          border: Border.all(color: IiOsColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Column(
          children: [
            Text(
              'Tap a part to describe it',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: AspectRatio(
                aspectRatio: kind == CharacterDesignKind.head ? 0.88 : 0.62,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: ValueKey('character-${kind.name}-silhouette'),
                        painter: _SilhouettePainter(
                          kind: kind,
                          selectedRegionId: selectedRegionId,
                          completion: completion,
                        ),
                      ),
                    ),
                    for (final entry in hotspots.entries)
                      if (byId[entry.key] case final region?)
                        Align(
                          alignment: entry.value,
                          child: _HotspotButton(
                            region: region,
                            selected: selectedRegionId == region.id,
                            completion: completion[region.id] ?? 0,
                            onPressed: () => onRegionSelected(region.id),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotspotButton extends StatelessWidget {
  const _HotspotButton({
    required this.region,
    required this.selected,
    required this.completion,
    required this.onPressed,
  });

  final CharacterDesignRegion region;
  final bool selected;
  final double completion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final complete = completion >= 1;
    final color = complete || selected ? IiOsColors.green : IiOsColors.muted;
    return Tooltip(
      message: 'Describe ${region.label.toLowerCase()}',
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${region.label}, ${(completion * 100).round()} percent complete',
        child: Material(
          color: complete
              ? IiOsColors.green.withValues(alpha: 0.18)
              : selected
              ? IiOsColors.surface
              : IiOsColors.surface.withValues(alpha: 0.88),
          shape: CircleBorder(
            side: BorderSide(
              color: selected ? IiOsColors.green : IiOsColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: ValueKey('character-hotspot-${region.id}'),
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 42,
              child: Icon(region.icon, size: 19, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
