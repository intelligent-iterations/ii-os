/// The ii-os design system: tokens, theme, and the primitive surfaces every
/// page is assembled from.
///
/// This package is the single source of truth for spacing, radii, breakpoints,
/// colour, and typography. A consuming app sets [IiOsTheme.light] once and then
/// reads every measurement from a token -- a raw numeric padding or an inline
/// `TextStyle` in a screen is a design decision made somewhere nobody will find
/// it again.
///
/// Run `example/` to see the whole system rendered, including the measured
/// contrast ratio of every palette entry.
library;

export 'src/a11y/contrast.dart';
export 'src/theme/ii_os_theme.dart';
export 'src/theme/palette.dart';
export 'src/tokens/breakpoints.dart';
export 'src/tokens/colors.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/icons.dart';
export 'src/tokens/identity.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/radii.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/typography.dart';
export 'src/tokens/widths.dart';
export 'src/widgets/appearance_toggle.dart';
export 'src/widgets/aspect_choice.dart';
export 'src/widgets/background_work_card.dart';
export 'src/widgets/choice_card.dart';
export 'src/widgets/chosen_tick.dart';
export 'src/widgets/decision_distribution.dart';
export 'src/widgets/duration_selector.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/gated_tab.dart';
export 'src/widgets/generation_slot.dart';
export 'src/widgets/generation_workspace.dart';
export 'src/widgets/ghost_mode_control.dart';
export 'src/widgets/identity_glyph.dart';
export 'src/widgets/ii_os_mark.dart';
export 'src/widgets/ii_os_wordmark.dart';
export 'src/widgets/inline_form_error.dart';
export 'src/widgets/kpi_card.dart';
export 'src/widgets/meta_chip.dart';
export 'src/widgets/media_download_button.dart';
export 'src/widgets/media_well.dart';
export 'src/widgets/pending_icon.dart';
export 'src/widgets/selection_rail.dart';
export 'src/widgets/permission_change_guide.dart';
export 'src/widgets/preset_scale.dart';
export 'src/widgets/prompt_enhance_action.dart';
export 'src/widgets/prompting_guide_button.dart';
export 'src/widgets/prompting_guide_content.dart';
export 'src/widgets/responsive_field_pair.dart';
export 'src/widgets/reviewed_commit_guide.dart';
export 'src/widgets/state_surfaces.dart';
