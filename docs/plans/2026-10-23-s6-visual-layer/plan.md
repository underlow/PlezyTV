# S6 — TV visual layer: plan

Contract: [`specification.md`](specification.md) (requirements, binding design,
acceptance A1–A16). Repository rules: [`docs/plezytv/tv-ui.md`](../../plezytv/tv-ui.md).
Checkout: `/Users/underlow/Projects/PlezyTV`, branch `flow/s6-visual-layer`.

## Result

A fork-owned TV visual layer under `lib/plezytv/tv_ui/` (theme, focus visuals,
tinted background, components) with tests under `test/plezytv/tv_ui/`, used by
no screen yet. Upstream change: `pubspec.yaml` font declaration only.

## Shared contracts (established by T1/T2, used by later tasks)

- **Tokens** — typed constants mirroring `docs/design/tokens.json` (spec 4.2).
- **Scale** — one way for any widget under the TV theme to convert design px to
  logical px (spec 4.1); components take design px.
- **TV theme wrapper** — opt-in widget providing scale, text styles, colors,
  `TextScaler.noScaling`, and keeping upstream `MonoTokens` (spec 4.3).
- **Strings** — fork-owned English strings class (spec 4.7); durations and
  counts Plezy already formats go through Plezy's formatters.
- **TV focusable** — the single focus primitive all components use (spec 4.4):
  wraps upstream `lib/focus/` logic (e.g. `FocusableWrapper` with
  `disableScale` / delegated border) and paints the PlezyTV focus kinds (ring,
  fill, outline), paint-only scale, pressed and disabled states and timings,
  instant when `DevicePerformance.isReduced`. Exposes focused/pressed state to
  its child so components style themselves. Later tasks must not re-implement
  focus handling.
- A test helper to pump a widget under the TV theme at a chosen logical size,
  in keyboard input mode, and to toggle reduced performance
  (`DevicePerformance.debugReset`).

Names, file split and private helpers are the developer's choice; keep them
consistent with the existing `tv_ui` code.

## Tasks

Order: T1 → T2 → (T3, T4, T5, T6, T7 in any order; T5 after T4) → T8.
Each task is a separate assignment; each commits only its own work and runs
`flutter analyze` plus its own tests and `test/plezytv`.

### T1 — Foundation: font, tokens, scale, theme, strings

Result: Manrope 400–800 bundled (static TTFs from the official Manrope release,
OFL license file alongside, under a fork-owned path such as
`assets/plezytv/fonts/`), declared in `pubspec.yaml` (the only upstream edit of
the stage). Tokens, scale, TV theme wrapper, strings class and the test helper
above.

Preserve: app theme outside the wrapper; existing fonts.

Checks:
- A1 — parity test reads `docs/design/tokens.json` from the repo root at test
  time; catches design values drifting from Dart. Verify it fails when a value is
  altered locally (then restore).
- A2 — scale at 960×540, 1280×1080, 1920×1080 and text scale 1.3; catches
  width-only scaling and leaked system text scale.
- A3 — styles inside, `tokens(context)` builds inside, `Theme.of` unchanged
  outside; catches breaking upstream widgets or restyling the app.
- `flutter build` is not required; `flutter test test/plezytv` and analyze pass.

### T2 — TV focus primitive

Depends on T1. Result: the TV focusable (shared contract above).

Preserve: upstream focus behavior (navigation, back, long-press, auto-scroll,
semantics); no edits in `lib/focus/`.

Checks:
- A4 — ring geometry, paint-only scale from a configurable origin (bottom edge
  for posters), neighbours unmoved; catches layout-affecting scale.
- A4b — key-down → ×0.97 of focused, key-up → one activation; catches double or
  missing activation and conflict with the long-press controller.
- A4c — disabled modes: skipped vs focusable-but-inert; catches activation of
  disabled items.
- A5 — 120/100/80 ms timings and instant reduced mode.

### T3 — Tint service and tinted background

Depends on T1. Result: tint computation and cache, tinted background widget and
plain variant (spec 4.5). Fetch, decode and clock injectable for tests; pixel
analysis via `compute` or equivalent; source through upstream image URL
builder and cache manager (`MediaImageHelper` / `image_cache_service.dart`);
reuse the pixel-reading approach of `lib/utils/tone_mapped_logo_image.dart`.

Checks: A6 (clamp, grey → none, cache counter, failure), A6b (debounce, no
intermediate fetch, first item no crossfade), A6c (contrast ≥ 4.5), backdrop
decode width ≤ 1280 and gradient-only on backdrop failure. Catches UI-thread
work, refetch per focus move and unreadable text.

### T4 — Card components

Depends on T2. Result: poster (row/grid/season sizes), episode thumbnail,
badges (watched, unwatched + focused caption, on server), progress bar,
skeletons (spec 4.6.1, 4.6.2, 4.6.8, 4.6.11). Data from `MediaItem` via Plezy
getters (`isWatched`, `unwatchedCount`, progress); images via
`OptimizedMediaImage`.

Checks: A4 on the real poster (title style change, caption not scaled), A11,
A14, A15 skeleton part. Catches own watch-state logic diverging from Plezy and
decode at full image size.

### T5 — Horizontal row

Depends on T4 (uses the poster in tests; the row itself takes any card
builder). Result: spec 4.6.3.

Checks: A7 (scroll rule, lazy building with margin, focus memory, focus-inside
reporting), header/headroom geometry, instant scroll when reduced. Catches
eager building of all items and focus jumping on re-entry.

### T6 — Buttons, chips, tabs, ratings

Depends on T2. Result: spec 4.6.4–4.6.7. Ratings use Plezy's
`mediaRatingsFor`, `mediaRatingLabel`, `ratingInfoForSource` (in
`lib/widgets/media_rating_badge.dart`, `lib/utils/rating_utils.dart`) without
reordering or filtering.

Checks: A8, A9, A10, A15 chip part. Catches own rating ordering/formatting,
tab selection without debounce, label-less primary button.

### T7 — Side menu and settings item

Depends on T2. Result: spec 4.6.9, 4.6.10; menu items supplied by the caller,
no navigation wiring.

Checks: A12 (width clip, not scale; scrim; marker; item states), A13.

### T8 — Integration and documentation

Depends on T1–T7. Result: update `docs/plezytv/tv-ui.md` with a short section on
the visual layer (where tokens/theme/focusable/components live, the opt-in theme
rule, units, logic-from-Plezy rule, test helper). No code changes beyond fixes
for integration issues found here.

Checks: A16 — `git diff <base>..HEAD --stat` touches upstream only in
`pubspec.yaml` (plus `docs/design/tokens.json`, fork-owned paths and assets);
full `flutter test` and `flutter analyze` pass; any pre-existing failures on the
base commit are identified by running them on the base, not assumed.

## Verification summary

Each A-case is owned by the task listed above. Whole-change review follows T8.
No device run is planned in S6 (spec §7).
