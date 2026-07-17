# HUMMI Brand Guidelines

The palette lives in `Foundations/Brand.swift`. Never use raw hexes in views.

## Tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `Brand.lime` → `Brand.limeDeep` | #A3F063 → #6AD634 | same | THE hero colour, always as `Brand.limeGradient` |
| `Brand.forest` | #173300 | same | Text/glyphs ON lime surfaces |
| `Brand.ink` | #173300 | #D9F7BF | Text/glyphs on the canvas |
| `Brand.canvas` | off-white | forest-black | Screen backgrounds that aren't plain white |
| Record red | #FF6B5C → #D11726 | same | The record control ONLY |

## The 5–10% rule (the law of this design system)

**Lime may cover at most 5–10% of any screen, and only on the single most
important element.** Everything else is forest ink, forest tints
(`Brand.ink.opacity(...)`), neutrals, or white. If two things on a screen
are lime, one of them is wrong.

Who gets the lime, per screen:
- **Home (idle)**: the import button (`.primary`) plus the script button
  at low intensity (`.secondary`) — together well under 10%. The red
  record button stays the focal point. While recording, the live
  waveform takes the lime; a toggle that is ON (script open) goes full
  lime.
- **Recorded review**: the "Make it Studio" pill.
- **Studio**: the "Save" pill. (Orbs/tiles have their own palettes —
  they are content, not chrome.)
- **Save screen**: the "Save Audio" pill.

## Red — the one exception

Record red exists for exactly one control: the record/stop button.
Simple treatment: a large flat two-stop gradient disc with a hairline
highlight — SOLID at rest (no inner dot); the white stop square appears
only while recording. No gloss, no halos, no glow shadows. Nothing
else in the app may be red (destructive actions communicate through
the warning haptic + confirmation alerts, not colour).

## Component rules

- **Primary pill** (`GlowPillButton` defaults): lime gradient, forest
  label. One per screen, max.
- **Inverted secondary**: forest fill, lime label (e.g. "Share as Video").
- **Neutral secondary / toolbar**: gray or glass, never lime.
- **Icon buttons** (`GlowIconButton`): a two-tier hierarchy of exact
  inverses — `.primary` (lime wash + forest glyph; at most one utility
  per screen), `.secondary` (forest fill + lime-gradient glyph, the
  default — the everyday tier), `.quiet` (plain ink chrome for controls
  that should recede, e.g. playback). A toggled-ON state always goes
  full lime. Buttons are generous: ~72–80pt wide capsules; the record
  disc is 92pt.
- **Type**: eyebrow = footnote semibold, tracked, uppercase, ink 55%;
  display = SERIF (New York) black, uppercase, in ink; body = regular SF.
  Numerals (timers) = SF Rounded heavy monospaced digits.
- **Feels**: every button keeps its role haptic + sound (ButtonFeel).

## Do / Don't

- DO let white/canvas breathe — the restraint is what makes lime loud.
- DO use `Brand.ink.opacity(0.3–0.65)` for secondary chrome and graphs.
- DON'T tint large surfaces lime (backgrounds, cards, full waveforms at rest).
- DON'T mix the old coral/sky palette back in.
- DON'T give two screen elements lime at once.
