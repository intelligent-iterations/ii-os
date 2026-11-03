import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'sections/breakpoints_section.dart';
import 'sections/colour_section.dart';
import 'sections/controls_section.dart';
import 'sections/decisions_section.dart';
import 'sections/depth_section.dart';
import 'sections/guidance_section.dart';
import 'sections/identity_section.dart';
import 'sections/scale_section.dart';
import 'sections/surfaces_section.dart';
import 'sections/typography_section.dart';

/// One entry in the gallery's navigation.
final class GallerySection {
  const GallerySection({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.build,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final Widget Function() build;
}

const gallerySections = <GallerySection>[
  GallerySection(
    title: 'Palette',
    blurb: 'Colour tokens with live WCAG contrast against both surfaces.',
    icon: LucideIcons.palette,
    build: ColourSection.new,
  ),
  GallerySection(
    title: 'Type',
    blurb: 'All fifteen text slots with their real metrics.',
    icon: LucideIcons.type,
    build: TypographySection.new,
  ),
  GallerySection(
    title: 'Identity',
    blurb: 'Hues and glyphs that say which one, never how is it.',
    icon: LucideIcons.shapes,
    build: IdentitySection.new,
  ),
  GallerySection(
    title: 'Scale',
    blurb: 'Spacing, icon sizes, content widths, and radii at true size.',
    icon: LucideIcons.ruler,
    build: ScaleSection.new,
  ),
  GallerySection(
    title: 'Breakpoints',
    blurb: 'Thresholds evaluated live against the current window.',
    icon: LucideIcons.monitorSmartphone,
    build: BreakpointsSection.new,
  ),
  GallerySection(
    title: 'Surfaces',
    blurb: 'Loading, empty, error, and the shared cards.',
    icon: LucideIcons.layers,
    build: SurfacesSection.new,
  ),
  GallerySection(
    title: 'Depth & motion',
    blurb: 'Elevation, timing, and the generation slot in every state.',
    icon: LucideIcons.sparkles,
    build: DepthSection.new,
  ),
  GallerySection(
    title: 'Controls',
    blurb: 'Material components as the ii-os theme dresses them.',
    icon: LucideIcons.mousePointerClick,
    build: ControlsSection.new,
  ),
  GallerySection(
    title: 'Decisions',
    blurb: 'Decision distributions and tabs gated on an installed runtime.',
    icon: LucideIcons.listChecks,
    build: DecisionsSection.new,
  ),
  GallerySection(
    title: 'Guidance',
    blurb: 'In-context help for model prompts and external setup steps.',
    icon: LucideIcons.bookOpenText,
    build: GuidanceSection.new,
  ),
];
