import 'package:flutter/material.dart';

/// Design units are pixels on a 1920 × 1080 canvas. Colors use RGBA in the source.
abstract final class TvTokens {
  static const color = (
    bg: (
      base: Color(0xFF0E0F12),
      tintStrength: 0.44,
      tintSaturationMax: 0.45,
      tintLightnessRange: [0.1, 0.18],
      scrimTop: Color(0x000E0F12),
      scrimBottom: Color(0xF20E0F12),
      scrimLeft: Color(0xE60E0F12),
      skeleton: Color(0xFF1A1C21),
      skeletonLine: Color(0xFF24272D),
    ),
    surface: (
      level1: Color(0xFF1A1C21),
      level2: Color(0xFF24272D),
      level3: Color(0xFF2F333A),
      overlay: Color(0xA6000000),
      scrim: Color(0xB30E0F12),
    ),
    text: (
      primary: Color(0xFFF2F3F5),
      secondary: Color(0xFFB4B8C0),
      tertiary: Color(0xFF7C818B),
      onAccent: Color(0xFF16130A),
      onFocus: Color(0xFF0E0F12),
    ),
    accent: (normal: Color(0xFFE5A00D), pressed: Color(0xFFC98A05), subtle: Color(0x33E5A00D)),
    focus: (ring: Color(0xFFFFFFFF), fill: Color(0xFFF2F3F5)),
    disabled: (fill: Color(0x8024272D), text: Color(0xFF5A5E66)),
    rating: (
      imdb: Color(0xFFF5C518),
      tmdb: Color(0xFF01B4E4),
      rtFresh: Color(0xFFFA320A),
      rtRotten: Color(0xFF6AC238),
      audience: Color(0xFFB4B8C0),
      plexCritic: Color(0xFFE5A00D),
    ),
    status: (
      watched: Color(0xFF4CAF7A),
      progressTrack: Color(0x33FFFFFF),
      progressFill: Color(0xFFE5A00D),
      unwatchedBadge: Color(0xFFE5A00D),
      error: Color(0xFFE5534B),
      onServer: Color(0xFF4CAF7A),
    ),
  );
  static const font = (
    family: "Manrope",
    fallback: ["Inter", "Roboto"],
    weights: (regular: 400, medium: 500, semibold: 600, bold: 700, extrabold: 800),
  );
  static const type = (
    display: (size: 56, lineHeight: 64, weight: 800, usage: "Hero title when no logo artwork"),
    headline: (size: 40, lineHeight: 48, weight: 700, usage: "Detail screen title, screen title"),
    title: (size: 28, lineHeight: 36, weight: 700, usage: "Row headers, section headers"),
    bodyLarge: (size: 24, lineHeight: 34, weight: 400, usage: "Hero/detail description (max 3 lines)"),
    body: (size: 22, lineHeight: 30, weight: 500, usage: "Card titles, list items, metadata line"),
    label: (size: 22, lineHeight: 28, weight: 600, usage: "Buttons, tabs, menu items"),
    caption: (size: 18, lineHeight: 24, weight: 500, usage: "Card subtitle (year, S1 E1), durations"),
    badge: (size: 16, lineHeight: 20, weight: 700, usage: "Badges, tech chips"),
  );
  static const space = (
    xxs: 4,
    xs: 8,
    sm: 12,
    md: 16,
    lg: 24,
    xl: 32,
    xxl: 48,
    xxxl: 64,
    safeX: 96,
    safeY: 54,
    rowGap: 48,
    cardGap: 24,
    rowHeaderToCards: 16,
    contentLeft: 200,
    actionsGap: 24,
  );
  static const radius = (xs: 4, sm: 8, card: 10, button: 12, iconButton: 16, chip: 8, panel: 16, badge: 6);
  static const size = (
    poster: (w: 216, h: 324, ratio: "2:3", perRowVisible: 7),
    posterGrid: (w: 228, h: 342, columns: 6, gap: 32),
    episode: (w: 400, h: 225, ratio: "16:9", perRowVisible: 4),
    seasonPoster: (w: 160, h: 240),
    castAvatar: (d: 140),
    button: (h: 64, minW: 200, padX: 32, iconSize: 28, iconGap: 12),
    iconButton: (w: 64, h: 64, iconSize: 30),
    chip: (h: 36, padX: 14),
    tab: (h: 52, padX: 24, underline: 4),
    sidebar: (collapsedW: 136, expandedW: 392, padLeft: 32, itemW: 72, itemH: 64, iconSize: 32, currentMarker: [4, 32]),
    rightPanel: (w: 600, iconSize: 28, background: Color(0xF21A1C21)),
    settingsItem: (h: 88, iconSize: 36, maxW: 1200),
    progressBar: (h: 6),
    unwatchedBadge: (minW: 36, h: 32),
    hero: (h: 600, compactH: 420, textMaxW: 860, logoMaxW: 560, logoMaxH: 200),
    focusRing: (width: 4, offset: 3),
    letters: (w: 48, itemH: 24, focusedH: 32, x: 1776),
    keyboard: (key: 64, gap: 12, columns: 6, panelW: 444, panelX: 200, resultsX: 740),
    buttonSmall: (h: 52, padX: 24),
  );
  static const focus = (
    cardScale: 1.08,
    buttonScale: 1.05,
    listItemScale: 1.0,
    pressedScale: 0.97,
    unfocusedSiblingOpacity: 1.0,
    disabledOpacity: 0.4,
    episodeScale: 1.05,
  );
  static const motion = (
    focusIn: 120,
    focusOut: 100,
    press: 80,
    rowScroll: 150,
    bgTintCrossfade: 400,
    heroCrossfade: 250,
    heroDebounce: 300,
    sidebarExpand: 180,
    curve: "easeOutCubic",
  );
}
