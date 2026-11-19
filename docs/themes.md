# Themes

A theme is one JSON file in `Sources/NotchTheme/Themes/`, named by its id. Adding a theme is adding
a file: the next build lists it in Settings › Appearance › Theme, and `ThemeTests` checks every token
in it. Themes share the fonts in `Fonts/` and the icon sets in `Icons/`, and name them; they hold
no code.

The notch reads the chosen theme from the environment (`\.theme`, set once at NotchView's root).
Views use the theme's colors as shape styles (`.themeInk`, `.themeSecondary`, `.themeTertiary`,
`.themeFill`, `.themeAccent`, `.themeOnAccent`, `.themeHighlight`), `theme.color(.ink)` where they
need a `Color`, and `.themeFont(.body, size:weight:)` for type. So `.white.opacity(0.55)` becomes
`.themeInk.opacity(0.55)`, which is the same pixels in Black.

## Versions

- `schema` is the format version. The app skips a file whose `schema` is newer than it reads
  (`Theme.newestSchema`), so a theme made for a later version never draws wrong in an older one.
- Unknown keys are ignored: a new optional key doesn't need a new schema, and leaving it out keeps
  the look a theme had without it.
- A new enum value, or a new required key, bumps `schema`. An older app meets an unknown enum value
  as an invalid file and leaves the theme out (the error names the key in the log).
- An id the app no longer has, stored in Preferences, draws as Black and stays stored.

## Keys

Required unless marked optional.

| Key | Values |
| --- | --- |
| `schema` | `1` |
| `id` | `[a-z0-9-]+`, the file's name; what Preferences stores. `black` and `glass` are the names the black/glass choice used before themes were files. |
| `name` | the picker's label |
| `order` | optional; the picker sorts by it, then by name (default 1000). Black is 0. |
| `appearance` | `dark` or `light`: the open notch's color scheme, for system controls and `.primary`/`.secondary`. Closed, the notch is always dark. |
| `surface.kind` | `solid`, or `glass` (Liquid Glass on macOS 26 and later, with a live blur under it) |
| `surface.color` | the open notch's fill, and glass's fallback (before macOS 26, Reduce Transparency, Increase Contrast). Closed, the notch is black in every theme, to hide in the camera housing. |
| `surface.band` | optional: a band of this color across the top, behind the camera and the header, with the sheet below it; over glass, a strip as tall as the camera housing |
| `surface.border` | optional: `{"color", "width"}`, a frame around the sheet, drawn inside the notch's edge |
| `surface.pattern` | optional: `{"kind", "color", "spacing"}`, a texture over the sheet: `dots`, or `grid` (graph paper) |
| `surface.glow` | optional: `{"colors", "strength", "radius"}`, light in those colors fading in from the edge, and a rim of them on it. `strength` (0...1) is where the Glow slider in Settings starts. It stays inside the notch, so it never catches a click, doesn't move, and Reduce Transparency keeps only the rim. |
| `closed.ink` | optional: text and icons on black (the closed notch, the header on a band). Needed by a light theme, whose ink is dark. |
| `accentChoices` | optional: accents to pick from in Settings; `colors.accent` is the default |
| `cards` | optional: `{"colors": [...], "ink"}`, the Home tab's cards in those colors in turn, their words in that ink; without it they sit on `colors.fill` |
| `tabs` | optional: `icons` (the default) or `text`, the tabs' names while they all fit the header |
| `colors.ink`, `.secondary`, `.tertiary` | text and icons |
| `colors.fill` | platters, tracks, and chips |
| `colors.accent` | lit controls and selection; `"system"` is macOS's accent color |
| `colors.onAccent` | text and icons on an accent fill |
| `colors.highlight` | optional: the prompter's current word, search matches; the accent without one |
| `fonts.display`, `.body`, `.mono` | `{"family": "system"}` or a family in Fonts/; optional `design` (system only: `default`, `rounded`, `serif`, `monospaced`), `weight` (overrides the view's: `ultralight` … `black`), `scale` (size multiplier) |
| `icons.set` | a folder in Icons/ |
| `icons.rendering` | optional, symbol sets only: `monochrome` (the default) or `hierarchical` |
| `icons.stroke`, `icons.cap` | optional, line sets only: replace every stroke-width in the set's SVGs, and `square` gives square ends and mitered joins |
| `radii.notchTop`, `.notchBottom` | the open notch's corners |
| `seekBar` | `line` (width), `cap` (`round`, `square`), `rest` (`solid`, `dotted`, `dashed`), `head` (`bar`, `dot`, `block`), `fill` (`artwork`, `accent`, `ink`); optional `played` (`solid`, `dotted`, `dashed`) and `headFill` |
| `waveform` | `bar` (width), `gap`, `shape` (`round`, `square`, `led`), `fill` (`artwork`, `accent`, `ink`); optional `peak`, a column's color at its loudest |
| `mascot` | optional: a little character at the head of the tab row, by the name of one the app draws (`Theme.mascots`: `heart-eyes`); an unknown one draws nothing |
| `skins` | optional: `musicPlayer`, `tabRow`, `closedNotch`, each the name of a skin the app ships (`SkinSlot.shipped`). A missing or unknown one draws the default view. |

Colors are `#RRGGBB` or `#RRGGBBAA`. A fill is `artwork` (the now-playing artwork's color, or ink
without artwork), `accent`, `ink`, or `gradient` (the glow's colors along the seek wave and across
the waveform, and the accent where one color is needed).

## Icon sets

`Icons/<set>/` holds one SVG per role, named by the role, plus the set's `LICENSE` and `set.json`
(its name, version, license, URL, `kind`, and `source`: the upstream name of each file). Roles are
the `FeatureID` raw values (`media`, `sound`, `shelf`, …) and the header's `apps`, `apps-on`,
`pin`, `pin-on`, `settings`, `edit`, `done`. A new feature adds one file to every set; `ThemeTests`
names any set missing one, and checks that a set's tab icons look one size in the row.

A symbol set (`sf-symbols`) ships no SVGs: its `set.json` has `"kind": "symbols"` and a `symbols`
map of role to SF Symbol name, which the system draws. Pick names that exist on macOS 14.6.

## Fonts

`Fonts/<Family>/` holds the font files, unchanged from upstream, and their license (OFL-1.1, listed
in THIRD_PARTY_NOTICES.md). Every file there is registered once, when the themes load. A theme's
`family` must be a registered family name; `ThemeTests` checks it. Bundle only the weights a theme
uses, or a variable font when it's smaller.
