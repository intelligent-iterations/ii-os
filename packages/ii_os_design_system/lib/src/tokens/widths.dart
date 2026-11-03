/// Maximum content widths.
///
/// Distinct from `IiOsBreakpoints`, which asks how wide the *window* is. These
/// ask how wide a column of content should be allowed to get inside it, and the
/// answer is driven by reading comfort rather than by the device.
///
/// The audit found eight different `maxWidth` values, several a few pixels
/// apart -- 420, 460, 480 all doing the same job in different places.
abstract final class IiOsWidths {
  /// 420 -- a single-column form or a centred empty state. Roughly 60 characters
  /// at the body size, which is where a line stops being comfortable to read.
  static const form = 420.0;

  /// 520 -- a form that carries a preview or a secondary column.
  static const wideForm = 520.0;

  /// 720 -- a reading column: documentation, long explanations, review copy.
  static const prose = 720.0;

  /// 1200 -- a page of panels on a desktop console.
  static const page = 1200.0;

  /// The scale in order, for galleries and tests.
  static const all = <(String, double, String)>[
    ('form', form, 'Single-column form, centred empty state'),
    ('wideForm', wideForm, 'Form with a preview or second column'),
    ('prose', prose, 'Reading column for long copy'),
    ('page', page, 'Desktop console page of panels'),
  ];
}
