# StudioVocals — Design System

Modern, minimalist, "liquid glass," native to iOS 17+. Every element earns
its pixels. Dark theme is the default; light is equally polished. Code lives
in `HUMMI/DesignSystem/` (`Foundations/` + `Components/`).

## Tokens

### Spacing (`Spacing`)
Only these values, ever: **4 · 8 · 12 · 16 · 24 · 32 · 48**
(`xxs xs s m l xl xxl`). Primary content columns cap at `contentMaxWidth`
(640) for iPad / large phones.

### Corner radius (`Radius`) — always `.continuous`
- `card` **12** — cards, list rows
- `sheet` **16** — sheets, large containers
- `cta` **22** — the primary CTA

Use `Radius.rect(_)` for the shape or `.dsCorner(_)` to clip.

### Typography (`Font.ds*`)
SF Pro system fonts via text styles only — never hardcoded points; full
Dynamic Type. Weights: `.regular` body · `.semibold` section headers ·
`.bold` reserved for the CTA (`dsCTA`) and Before/After labels
(`dsToggleLabel`). Tokens: `dsTitle dsSectionHeader dsBody dsCallout
dsCaption dsCTA dsToggleLabel`.

### Color
Semantic system colors only (`.label`, `.secondaryLabel`, `.tertiaryLabel`,
`Color(.systemBackground)`, `.secondarySystemBackground`,
`.tertiarySystemFill`, `.separator`, `.tint`). One brand **AccentColor**
(electric indigo) in `Assets.xcassets` with light, dark, and high-contrast
variants, applied once via `.tint(.accentColor)` at the app root. Follow
60 (surface) · 30 (content) · 10 (accent). `red` is used only for the
record affordance (a universal, recognizable convention).

Text meets WCAG AA (4.5:1) in both themes. `ContrastChecker.ratio(_:on:)`
computes ratios; `.dsContrastAudit(foreground:on:)` overlays a ⚠︎ badge in
DEBUG when a pair fails. (SwiftUI can't scan arbitrary glyphs, so the audit
is opt-in at the text site.)

## Materials & elevation
- `.ultraThinMaterial` — floating controls (GlassToolbar, ProgressPill)
- `.thinMaterial` — inline chips, hints, sheet backgrounds
- `.regularMaterial` / `.thick` — sheets / modal contexts
- Elevation comes from material layering + hairline `Divider`s, **not
  drop shadows**. The single exception: the primary CTA's soft accent glow
  (`shadow` radius 20, opacity 0.15, y 0).

## Motion vocabulary (`Motion`)
- `standard` — `spring(response: 0.35, dampingFraction: 0.82)` for state
- `interactive` — gesture tracking
- `micro` — 120 ms confirmations
- `celebratory` — ≤ 500 ms beats
- `progress` — linear, determinate only
- Reduce Motion → `Motion.adaptive(_,reduceMotion:)` swaps scale/slide for a
  crossfade; CTA breathing and the toggle intro disable.

**Signature transition:** Record → Result zooms the waveform
(`waveformTransitionSource(in:)` on the record waveform +
`.navigationTransition(.zoom(sourceID: Motion.waveformTransitionID, in:))`
on the Result destination).

## Haptics (`Haptic`, via `.sensoryFeedback`)
record start `.impact(.light)` · record stop `.impact(.medium)` ·
enhancement complete `.success` · A/B toggle `.selection` · preset change
`.selection` · CTA tap `.impact(.medium)`. One event = one feedback.

## Components (`DesignSystem/Components/`)
`PrimaryCTA` · `GlassToolbar` · `BeforeAfterToggle` · `PresetChipRow`
(+`PresetChipModel`) · `WaveformView` · `LevelMeter` · `ProgressPill` ·
`SectionHeader` · `InlineHint` · `EmptyStateView`. Each ships previews in
light, dark, Dynamic Type `.accessibility2`, and RTL.

## Accessibility
Every interactive element carries a label, a hint, and a value where state
matters (the toggle announces "Before" / "After"). Minimum tap target
44×44. No truncation up to `.accessibility3`. Usable with Reduce Motion,
Reduce Transparency, and Increase Contrast on.

## Onboarding & permission pattern (Step 6.2)
First launch is gated by `@AppStorage("hasCompletedOnboarding")` in
`AppRootView` (a conditional full-screen swap, chosen over `.fullScreenCover`
so the dismiss can spring and the main app's audio session isn't activated
beneath the demo). The reusable rule it establishes: **always precede a
system permission prompt with a custom explainer** that states the concrete
value and the trust hook *before* the OS alert — the mic screen leads with
the on-device promise, then triggers `AVAudioApplication.requestRecordPermission`
on the CTA, and never holds the app hostage on denial (Open Settings /
Continue anyway). Apply the same shape to any future ask (notifications,
etc.): explain → user-initiated CTA → system prompt → graceful denial path.
Onboarding consumes only DesignSystem tokens/components; the sole additions
are two hero title tokens (`dsHeroTitle`, `dsHeroTitleCompact`) — a
contained, justified exception to "bold reserved" for the first-run heroes.

## App icon
Placeholder only: accent gradient + bold white `waveform.and.microphone`.
Chosen because the app is one motion — a **microphone** capturing a voice
and a **waveform** being transformed — so the glyph states input and
output at a glance. Final icon is out of scope for this step.
