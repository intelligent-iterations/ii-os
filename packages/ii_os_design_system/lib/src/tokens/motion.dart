import 'package:flutter/widgets.dart';

/// Timing and easing, so movement is a system rather than a per-widget guess.
///
/// Delight in an operator console has to be earned and bounded. These tokens
/// exist so a generation finishing can feel like something arrived, while a
/// permission error, a destructive confirm, and a failed job stay still -- a
/// console that bounces when it denies you is a console you stop trusting.
///
/// Every duration must be read through [of], which returns [Duration.zero]
/// when the viewer has asked their system for reduced motion. A hard-coded
/// `Duration(milliseconds: 200)` bypasses that preference and is the reason
/// this token set exists at all.
abstract final class IiOsMotion {
  /// State that should feel like it was already true: hover, focus ring.
  static const instant = Duration(milliseconds: 90);

  /// Direct response to a tap: selection, toggle, ripple settle.
  static const quick = Duration(milliseconds: 160);

  /// The default for anything entering or leaving the page.
  static const base = Duration(milliseconds: 240);

  /// Larger surfaces travelling further: sheets, drawers, dialogs.
  static const slow = Duration(milliseconds: 420);

  /// A generated artifact taking its place. The one duration allowed to be
  /// slow enough to notice, because noticing is the point.
  static const arrival = Duration(milliseconds: 620);

  /// Entering: decelerate into place.
  static const enter = Curves.easeOutCubic;

  /// Leaving: accelerate away. Exits should not linger.
  static const exit = Curves.easeInCubic;

  /// Moving between two on-screen states.
  static const standard = Curves.easeInOutCubic;

  /// A small overshoot, for arrival only. Never for status or errors.
  static const arrive = Curves.easeOutBack;

  /// [duration], or nothing at all when the viewer prefers reduced motion.
  static Duration of(BuildContext context, Duration duration) {
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return disabled ? Duration.zero : duration;
  }

  /// Whether decorative movement should be suppressed entirely.
  ///
  /// Shortening a shimmer is not enough -- a looping animation still pulls the
  /// eye. Ask this before starting one, and render the still state instead.
  static bool decorativeAllowed(BuildContext context) =>
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The durations with the job each one does, for the gallery.
  static const all = <(String, Duration, String)>[
    ('instant', instant, 'Hover, focus ring'),
    ('quick', quick, 'Selection, toggle'),
    ('base', base, 'Enter and leave'),
    ('slow', slow, 'Sheets, drawers, dialogs'),
    ('arrival', arrival, 'A generated artifact landing'),
  ];
}
