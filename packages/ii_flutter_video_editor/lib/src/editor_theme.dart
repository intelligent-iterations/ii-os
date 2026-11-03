import 'package:flutter/material.dart';

@immutable
final class EditorThemeData {
  const EditorThemeData({
    this.backgroundColor = const Color(0xff111318),
    this.surfaceColor = const Color(0xff1b1e25),
    this.rulerColor = const Color(0xff242832),
    this.dividerColor = const Color(0xff353a47),
    this.videoClipColor = const Color(0xff365f9d),
    this.audioClipColor = const Color(0xff437a52),
    this.captionClipColor = const Color(0xff7b4d91),
    this.selectedColor = const Color(0xfff2b84b),
    this.playheadColor = const Color(0xffff6257),
    this.textColor = const Color(0xfff3f5f8),
    this.mutedTextColor = const Color(0xffa8afbd),
    this.laneHeight = 58,
    this.rulerHeight = 32,
    this.headerWidth = 116,
    this.clipRadius = 8,
  });

  factory EditorThemeData.fromColorScheme(ColorScheme colors) =>
      EditorThemeData(
        backgroundColor: colors.surface,
        surfaceColor: colors.surfaceContainerHighest,
        rulerColor: colors.surfaceContainer,
        dividerColor: colors.outlineVariant,
        videoClipColor: colors.primaryContainer,
        audioClipColor: colors.secondaryContainer,
        captionClipColor: colors.tertiaryContainer,
        selectedColor: colors.primary,
        playheadColor: colors.error,
        textColor: colors.onSurface,
        mutedTextColor: colors.onSurfaceVariant,
      );

  final Color backgroundColor;
  final Color surfaceColor;
  final Color rulerColor;
  final Color dividerColor;
  final Color videoClipColor;
  final Color audioClipColor;
  final Color captionClipColor;
  final Color selectedColor;
  final Color playheadColor;
  final Color textColor;
  final Color mutedTextColor;
  final double laneHeight;
  final double rulerHeight;
  final double headerWidth;
  final double clipRadius;
}
