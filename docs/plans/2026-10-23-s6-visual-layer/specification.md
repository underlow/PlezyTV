# S6 — TV visual layer: specification

Project: `docs/projects/plezy-tv/project.md`, stage S6. Profile `medium`.

> From the project: this is a high-level plan based on the user's request; its
> technical claims are not verified. This specification is the contract for S6.

## 1. Goal

Move the PlezyTV design system (`docs/design/`) into fork-owned code so later
screen stages (S7–S12, S14) build screens from ready parts: tokens, Manrope,
focus visuals, artwork-tinted background and shared components with all states.
S6 delivers no screens and changes nothing visible in the running app.

Looks come from `docs/design/tokens.json` (numbers) and `design-system.md`
(rules); `screens/00-components.png` is a reference. **Logic comes from Plezy**:
which data is shown, in what order and format (ratings, durations, watched and
progress state, unwatched counts) is taken from existing Plezy code and data;
the design only styles it. Where the design implies different logic, Plezy wins
unless the user explicitly agreed a change.

## 2. User decisions (2026-10-23)

- Acceptance by widget tests only; no gallery screen. Visual check on a TV
  happens in S7–S12 on real screens.
- Fork-owned strings English only; no upstream slang changes. Templates stay
  whole parameterized strings so a locale can be added later.
- Side menu and settings item: components only; navigation wiring is S12.
- Tint strength: 0.44 (as in design-system.md and the mockups);
  `tokens.json` `color.bg.tintStrength` corrected from 0.22 to 0.44 in this
  stage. Chosen by coordinator at the user's request; easy to change later.
- The Android system font-size (accessibility) setting is ignored inside the TV
  theme; sizes follow the design.
- Ratings: the set, order, value formatting and source icons come from Plezy
  (`mediaRatingsFor`, `mediaRatingLabel`, `ratingInfoForSource`, including
  unattributed and community ratings as Plezy shows them); the design supplies
  only the look. Design's fixed order and Kinopoisk are not adopted.

## 3. Constraints

- Code under `lib/plezytv/tv_ui/`, tests under `test/plezytv/tv_ui/`, per
  `docs/plezytv/tv-ui.md`.
- Upstream edits: only `pubspec.yaml` to declare the bundled Manrope font. Font
  files and OFL license live under a fork-owned asset path. No other upstream
  file changes, no screen hooks.
- Upstream screens inside `TvShell` keep their look; the TV theme applies only to
  subtrees that opt in.
- Mi Box 4 rules (design-system §0.2, README): no blur, glass, blurred shadows or
  glow; only scale and opacity animate (plus the side-menu width clip); flat
  scrims; backdrop decoded ≤ 1280 px wide; skeletons static. When
  `DevicePerformance.isReduced` is true, focus, press, scroll and crossfade
  transitions are instant.
- General design rules apply to every component: no pills or circles on buttons
  (only cast avatars are round), focus never shown by accent color, safe margins
  `safeX 96`, `safeY 54` and `contentLeft 200` exposed for screens.
- No new runtime package dependency.

## 4. Behavior

### 4.1 Units and text scale
Tokens are px at 1920×1080. The TV layer converts design px to logical px with
`scale = min(width / 1920, height / 1080)` of the `MediaQuery` size at the TV
theme root, so the UI occupies the same share of any TV screen regardless of
its size or density (e.g. a 960-logical-wide 1080p box gives 0.5). Components
accept sizes in design px. Inside the TV theme `MediaQuery.textScaler` is
`TextScaler.noScaling`.

### 4.2 Tokens
Groups `color`, `font`, `type`, `space`, `radius`, `size`, `focus`, `motion` are
typed Dart constants (`player` left for S9/S14; `$comment` ignored). A test reads
`docs/design/tokens.json` at test time and checks every mirrored value, so a
design change not mirrored in Dart fails.

### 4.3 Theme and font
An opt-in TV theme wrapper gives its subtree Manrope text styles for the type
scale (`display` … `badge`: size, line height, weight, converted per 4.1), the TV
colors, no text scaling, and keeps the upstream `MonoTokens` extension so upstream
widgets inside still build. Manrope 400–800 is bundled. Fallback per tokens.

### 4.4 Focus visuals
TV components reuse upstream focus logic from `lib/focus/` (key handling,
directional navigation, scroll-into-view, back, long-press; e.g.
`FocusableWrapper` with its own border and scale turned off) and draw PlezyTV
visuals themselves:
- **Focused:** white ring 4 px with 3 px gap (posters, episodes) or white fill
  (buttons, tabs, menu items) or `surface.3` + 4 px outline (settings items), plus
  scale: cards 1.08, episodes 1.05, buttons/tabs/chips 1.05, list and settings
  items 1.0. Scale is paint-only: neighbours and layout do not move.
- **Pressed:** while select/enter is held on a focused item, scale ×0.97 of the
  focused size (and the component's pressed colors); release activates once
  through the normal upstream select path. Long-press behavior is unchanged.
- **Disabled:** opacity 0.4, no ring/fill, does not activate. Posters, episodes,
  tabs, chips and menu items are skipped by focus; buttons and settings items stay
  focusable so their reason can be read, but select does nothing.
- **Timing:** focusIn 120 ms, focusOut 100, press 80, easeOutCubic; instant when
  reduced (as upstream `FocusTheme` does).
- Focus visuals appear in keyboard/D-pad mode as upstream decides
  (`InputModeTracker`); pointer and touch are not a target for S6.

### 4.5 Artwork-tinted background
- **Source:** a separate small fetch of the item's poster (thumb) through the
  upstream image URL builder and cache, fixed small width (≈ 64 px). Local or
  offline items use their local artwork if available; otherwise no tint.
- **Tint:** dominant color of that image, ignoring near-black, near-white and
  near-grey pixels; if nothing remains, no tint. Clamped in HSL to saturation
  ≤ 0.45 and lightness 0.10–0.18. Pixel analysis runs off the UI thread. Cached
  per server + item key in a bounded LRU (at most a few hundred entries); a
  failure is cached as "no tint" for that item for the session.
- **Background:** vertical gradient from `lerp(bg.base, tint, tintStrength)` at
  the top to `bg.base` at 85% height. Text on it keeps contrast ≥ 4.5:1 with
  `text.primary` (guaranteed by the clamp; tested). Optional backdrop at the right
  (1300×780, decode ≤ 1280 px wide) fading into the background over 55% of width
  from the left and 45% of height from the bottom, plus a left scrim 1100 px under
  text. Without a backdrop or on its failure — gradient only.
- **Changes:** the first item is shown without crossfade. A new item takes effect
  only after it stayed current for 300 ms (`heroDebounce`); then the tint is
  requested and, when ready, the background crossfades over 400 ms
  (`bgTintCrossfade`) from its current look. A change during a crossfade starts
  the next one from the current look. Items replaced within 300 ms are never
  fetched. No tint → crossfade to `bg.base` gradient. Instant when reduced.
- **Plain variant:** `bg.base` with a light cool tint at the top for library,
  search, Watchlist and state screens.
- `motion.heroCrossfade` (250) belongs to the S12 hero, not to this background.

### 4.6 Components
Sizes, colors and type from tokens; data from Plezy's `MediaItem` (or plain
values); images through upstream `OptimizedMediaImage`, decode limited to the
displayed size. All states per design-system §5.

1. **Poster 2:3** — row 216×324, grid 228×342, season 160×240; radius 10;
   placeholder `surface.2`. Title `body` (one line, ellipsis) and caption
   `caption` tertiary 20 below. Focus: image ×1.08 from its bottom edge with the
   ring, title becomes primary w600; captions do not scale or move. Badges and
   progress per 8.
2. **Episode thumbnail 16:9** — 400×225, radius 10, progress bar 6 px inside the
   bottom edge; line 1 `S{n} E{m} · {title}` (`body`), line 2 duration or
   `{t} left` (`caption`); focus 1.05, same ring.
3. **Horizontal row** — header `title` at x = 200 with optional counter
   `caption`; header to cards 16 + 24 headroom (40 total); card gap 24; cards
   continue past the right edge. Moving focus right keeps the focused card at the
   first visible slot once the row has scrolled away from index 0 (no scroll
   while focus is within the first visible slots); moving left mirrors it until
   index 0; the end of the row just stops. Scroll 150 ms (instant when reduced).
   Lazily builds visible cards plus about one screen of margin. The row is not
   focusable; it exposes whether focus is inside (listenable + callback) and
   returns focus to the last focused card when re-entered.
4. **Buttons** — primary: h 64, min width 200, pad 32, icon 28 + gap 12 + label
   `label`, `accent` fill + `onAccent` text; focused white fill, dark text ×1.05;
   pressed `accent.pressed` ×0.97; disabled `disabled.fill` + `disabled.text`;
   a label is required (empty label asserts). Secondary: same, `surface.3` +
   `text.primary`, focused white. Small secondary: h 52, pad 24. Icon button:
   64×64, radius 16, icon 30, `surface.3`, focused white ×1.05, caption
   `caption` 10 below shown only in focus with its space always reserved.
5. **Chips** — h 36, pad 14, radius 8, `badge` text. Genre: `surface.2` +
   `text.secondary`, focusable only when asked, states as a button. Technical:
   1.5 px `text.tertiary` outline, no fill, never focusable.
6. **Ratings** — Plezy's list for the item (see §2), each as a source plate 24 px
   high and value `body` w600, 24 between entries; not focusable. Plates use the
   design color where tokens define one (IMDb, TMDB, RT fresh/rotten by Plezy's
   own fresh/rotten determination, audience); other sources use Plezy's source
   icon/label with neutral styling. Empty list renders nothing.
7. **Tabs** — h 52, pad 24, `label`; block offset −24 so the first label is at
   x = 200. Normal `text.secondary`; selected `text.primary` + 4 px `accent`
   underline; focused white fill radius 12 ×1.05; pressed fill `text.secondary`;
   disabled 0.4. Focus resting 300 ms selects the tab (callback); OK selects at
   once. Focus entering the block lands on the selected tab.
8. **Badges** — top-right with offset 8, radius 6, `badge` text, not focusable:
   watched (32 square, `status.watched`, check) per Plezy `isWatched`; unwatched
   count (`accent`, min width 36, h 32) per Plezy `unwatchedCount`, and when its
   poster is focused the caption becomes `{n} unwatched` in accent; on server
   (top-left plate, `status.onServer`) as a flag supplied by the caller. Progress
   bar (6 px, track `status.progressTrack`, fill `status.progressFill`) per
   Plezy's in-progress state.
9. **Side menu** — collapsed: width 136, transparent, items 72×64 with pad 32,
   icon 32, no labels, current item marked by 4×32 `accent` bar on the left.
   Expanded (focus inside): 392 px `surface.1` panel with labels `label`, rest of
   the screen under flat `surface.scrim`; expansion animates the width clip over
   180 ms (instant when reduced), never a scale. Item states: focused white fill,
   pressed `text.secondary`, disabled 0.4. Items, current item and divider
   position are supplied by the caller.
10. **Settings item** — h 88, max width 1200, icon 36, title `body` + description
    `caption`, value `body` secondary and chevron on the right. Focused
    `surface.3` + 4 px white outline radius 12, no scale; pressed `surface.2` with
    outline; disabled 0.4 with its reason as the description.
11. **Skeletons** — static shapes for poster, episode and row in `bg.skeleton` /
    `bg.skeletonLine`, no animation.

Not in S6: search keyboard (S11), player parts (S9), hero (S12).

### 4.7 Strings
Fork-owned English templates for S6 components: `{t} left`, `{n} unwatched`,
`S{n} E{m} · {title}`, plus anything else a component needs. Durations `{t}` and
any count/plural wording Plezy already formats (e.g. seasons, episodes) use
Plezy's formatters (`formatDurationTextual` etc.), not new rules. Screen
templates (`Resume · {t} left`, …) are added by their stages.

## 5. Acceptance examples (widget tests; Ahem font, so text is checked by style and content)

- A1 Tokens: every mirrored Dart value equals `docs/design/tokens.json` read at
  test time; `tintStrength` is 0.44.
- A2 Units: logical 960×540 → 216 px poster is 108×162 logical and `title` font
  size 14, also with system text scale 1.3. Logical 1280×1080 → scale
  min(0.667, 1.0) = 0.667.
- A3 Theme: inside the wrapper `title` is family Manrope, w700, size/height per
  tokens; an upstream widget calling `tokens(context)` builds inside; outside the
  wrapper `Theme.of` is the app theme unchanged.
- A4 Focus (keyboard mode): focused row poster paints at 1.08 with a 4 px white
  ring at 3 px gap; its image bottom edge stays at the same y; neighbours, title
  and caption boxes do not move; title style becomes primary w600.
- A4b Press: select key-down on a focused poster → painted at 1.08×0.97; key-up →
  1.08 and the activation callback fired once.
- A4c Disabled: disabled poster has opacity 0.4, no ring and is skipped by
  directional focus; disabled settings item and button take focus but select
  does nothing.
- A5 Timing: normal → 60 ms after focus the scale is strictly between 1.0 and 1.08
  and at 120 ms it is 1.08; unfocus done at 100 ms. Reduced (`DevicePerformance`
  test reset) → after one pump no running animations and final values applied.
- A6 Tint: synthetic mostly-red image → S ≤ 0.45, L in 0.10–0.18; a mostly
  grey/black image → no tint; second request for the same item → no new fetch
  (counter); failure → gradient top equals `bg.base`.
- A6b Debounce: item A shown; B current, after 200 ms C current; 300 ms after C →
  exactly one fetch (C), crossfade finished 400 ms after the tint is ready; A's
  first display had no crossfade; B never fetched.
- A6c Contrast: for saturated red, yellow and white artworks the gradient top vs
  `text.primary` has contrast ≥ 4.5.
- A7 Row: 20 items; focusing right from index 0 does not scroll while within the
  visible slots, then keeps the focused card at the first visible slot; only
  visible + margin cards are built; leaving and re-entering returns to the last
  card; focus-inside reports true/false.
- A8 Buttons: empty label asserts; icon button has the same height focused and
  unfocused with the caption visible only when focused; primary pressed color is
  `accent.pressed`.
- A9 Ratings: for an item with ratings [imdb 7.1, rottenTomatoesCritic 8.5,
  letterboxd 8], the entries, order and value texts equal Plezy's
  `mediaRatingsFor` / `mediaRatingLabel`; item with only an unattributed
  `rating` → as Plezy shows it; no ratings → nothing rendered.
- A10 Tabs: focus resting 300 ms selects; moving away earlier does not; OK
  selects immediately; disabled tab is skipped and at 0.4; entering lands on the
  selected tab.
- A11 Badges/strings: watched item → watched badge; show with 12 unwatched →
  badge `12`, focused caption `12 unwatched`; `1 unwatched`; durations and season
  counts equal Plezy's formatter output.
- A12 Side menu: focus entering → at 90 ms the clip width is strictly between 136
  and 392 with children unscaled, at 180 ms 392 with scrim; leaving collapses;
  collapsed current item has the accent bar; pressed item fill
  `text.secondary`; disabled 0.4.
- A13 Settings item: focused has outline and no scale; pressed `surface.2` with
  outline; disabled shows its reason.
- A14 Episode: 40% progress → bar 6 px high inside the bottom edge, 160 design px
  wide; line 1 `S1 E3 · Title`; in-progress line 2 `{t} left`; focus 1.05.
- A15 Chips/skeletons: technical chip has no focus node; genre chip with
  focusable on takes focus and scales 1.05; skeleton has no running animations.
- A16 Isolation: the stage diff touches upstream only in `pubspec.yaml` (plus
  `docs/design/tokens.json` and fork-owned paths); the full `flutter test` suite
  and `flutter analyze` pass.

## 6. Out of scope

Screens and hooks (S7–S12, S14), search keyboard, player components, hero,
gallery screen, golden tests, translations, device performance measurement (S2).

## 7. Limits

Tests check geometry, styles, states and timing, not pixel looks (no goldens,
Ahem). Real appearance and Mi Box 4 performance are first checked in the screen
stages' screenshot acceptance.
