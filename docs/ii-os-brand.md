# ii-os brand

ii-os is the creative operations workspace from Intelligent Iterations. Its
brand should feel precise and calm: an operator surface that keeps complex
creative work moving without looking like a generic admin console.

## Name and voice

- Write the product name as `ii-os`: lowercase, hyphenated, and never `ii_os`
  in user-facing copy.
- The supporting line is **Creative operations, in motion.**
- Prefer short, direct status language that tells the user what is happening.

## Mark

The mark is a pair of lowercase `i` pillars. Together they also read as a pause
control: ii-os gives operators a clear place to observe, review, and resume
automated work. Evergreen represents active iteration; warm white represents
the human decision point.

`web/icons/ii-os-mark.svg` is the canonical web mark. The full-bleed
`web/icons/ii-os-mark-maskable.svg` is the source for maskable and Apple touch
icons. The two-pillar silhouette supplies pinned-tab and notification badge
assets. Flutter renders the same geometry in
`packages/ii_os_design_system/lib/src/widgets/ii_os_mark.dart`.

## Typeface

ii-os sets in **Manrope**, bundled as static instances at four weights (400,
600, 700, 800) and subset to Latin. It is geometric enough to stay precise at
interface sizes, with open counters and softly cut terminals that keep it from
reading cold, and it carries tabular figures so KPI cards and job tables stay
column-aligned as digits change. Provenance, licence, and the instancing and
subsetting recipe live in `packages/ii_os_design_system/fonts/README.md`.

Bundling is the point. Declaring `Arial` without shipping a font meant the app
rendered in Roboto on Android, Helvetica on iOS, and whatever the browser
resolved on web -- three different products wearing the same colours.

## Type scale

Defined once in `IiOsTheme.textTheme`; every slot Material offers is filled, so
`Theme.of(context).textTheme.<slot>` is always correct and an inline `TextStyle`
is always a smell. Tracking tightens as size grows.

| Slot | Size / weight | Use |
| --- | --- | --- |
| `displayLarge/Medium/Small` | 40/34/30 · 800 | Marketing and startup moments |
| `headlineLarge` | 30 · 700 | Page title |
| `headlineMedium` | 26 · 700 | Major section |
| `headlineSmall` | 22 · 700 | `PageFrame` title |
| `titleLarge` | 18 · 700 | Card and dialog title |
| `titleMedium` | 15 · 700 | Section heading, list row title |
| `titleSmall` | 13 · 700 | Dense label |
| `bodyLarge` | 15 · 400 | Long-form reading |
| `bodyMedium` | 14 · 400 | Default body |
| `bodySmall` | 12 · 400 · muted | Supporting and status text |
| `labelLarge` | 13 · 600 | Buttons and controls |
| `labelMedium` | 12 · 600 | Field labels |
| `labelSmall` | 11 · 700 · muted · +0.8 | Table headings, nav section headers |

## Core colors

| Token | Hex | Use |
| --- | --- | --- |
| Ink | `#171B1F` | Mark field, primary text |
| Evergreen | `#0B7661` | Action and progress |
| Signal mint | `#5ED6B2` | Mark highlight only |
| Canvas | `#F4F6F5` | App and startup background |
| Surface | `#FFFFFF` | Cards, inputs, app bar |
| Muted | `#606A73` | Supporting status text |
| Border | `#CDD5DA` | Structural hairline: card outlines, dividers, progress track |
| Border strong | `#7F8A93` | Interactive boundary: inputs, outlined buttons |

Two border tokens, because they answer to different rules. `Border strong` is
3.52:1 on surface and 3.25:1 on canvas, clearing the WCAG 1.4.11 non-text
contrast minimum of 3:1 that applies to anything identifying a control or its
state. `Border` is decorative separation and carries no such duty, so it stays
a quiet hairline. The single `#D9DFE3` token that preceded them was 1.34:1 and
was doing both jobs, which left every text-field edge effectively invisible to
low-vision users.

Every text colour clears WCAG AA on both backgrounds: ink 17.3:1, muted 5.5:1,
evergreen 5.6:1, blue 5.2:1, amber 5.0:1, red 5.9:1.

## Light and dark

ii-os ships a light and a dark palette: `IiOsPalette.light` and
`IiOsPalette.dark` in `packages/ii_os_design_system`, applied through
`IiOsTheme.light()` and `IiOsTheme.dark()`. The core colors above are the light
values; their dark counterparts live in `IiOsColorsDark`. Each mode is its own
set of values rather than a transformation of the other, and the design-system
contrast test walks both, so a dark-mode regression fails the build the same
way a light one does.

The app follows the operating system's preference until the viewer picks a
mode with the appearance toggle; `AppearanceController` remembers that choice
across sessions. Widgets read colour from `IiOsPalette.of(context)`, never a
`static const` token, so the same widget renders correctly in both modes (rule
13 in `docs/ii-os-frontend.md`).

The HTML bootstrap in `web/index.html` declares `color-scheme: light`, so the
startup surface before Flutter paints is always the light canvas.

## Spacing, radii, breakpoints

Tokens live in `lib/theme/ii_os_tokens.dart`: a 4pt spacing scale, five radii
with `6` as the house default, and breakpoints named for the decision they drive
(the first three follow the Material 3 window size classes). Raw numeric
literals in screens and widgets are a composition-rule violation -- see
`docs/ii-os-frontend.md`.

The HTML bootstrap surface and Flutter startup surface deliberately share the
same mark, copy, dimensions, typeface, and colors so the handoff reads as one
continuous load rather than two applications flashing between states.
