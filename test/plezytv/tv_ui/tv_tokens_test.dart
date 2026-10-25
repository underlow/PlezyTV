import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';

String rgba(Color color) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#${argb.substring(2)}${argb.startsWith('FF') ? '' : argb.substring(0, 2)}';
}

void main() {
  test('A1 every mirrored token equals the design source read at test time', () {
    final source = jsonDecode(File('docs/design/tokens.json').readAsStringSync()) as Map<String, dynamic>;
    source.remove(r'$comment');
    (source['player'] as Map<String, dynamic>).remove('postplay');
    const pl = TvTokens.player;
    final actual = {
      "color": {
        "bg": {
          "base": rgba(TvTokens.color.bg.base),
          "tintStrength": TvTokens.color.bg.tintStrength,
          "tintSaturationMax": TvTokens.color.bg.tintSaturationMax,
          "tintLightnessRange": [TvTokens.color.bg.tintLightnessRange[0], TvTokens.color.bg.tintLightnessRange[1]],
          "scrimTop": rgba(TvTokens.color.bg.scrimTop),
          "scrimBottom": rgba(TvTokens.color.bg.scrimBottom),
          "scrimLeft": rgba(TvTokens.color.bg.scrimLeft),
          "skeleton": rgba(TvTokens.color.bg.skeleton),
          "skeletonLine": rgba(TvTokens.color.bg.skeletonLine),
        },
        "surface": {
          "1": rgba(TvTokens.color.surface.level1),
          "2": rgba(TvTokens.color.surface.level2),
          "3": rgba(TvTokens.color.surface.level3),
          "overlay": rgba(TvTokens.color.surface.overlay),
          "scrim": rgba(TvTokens.color.surface.scrim),
        },
        "text": {
          "primary": rgba(TvTokens.color.text.primary),
          "secondary": rgba(TvTokens.color.text.secondary),
          "tertiary": rgba(TvTokens.color.text.tertiary),
          "onAccent": rgba(TvTokens.color.text.onAccent),
          "onFocus": rgba(TvTokens.color.text.onFocus),
        },
        "accent": {
          "default": rgba(TvTokens.color.accent.normal),
          "pressed": rgba(TvTokens.color.accent.pressed),
          "subtle": rgba(TvTokens.color.accent.subtle),
        },
        "focus": {"ring": rgba(TvTokens.color.focus.ring), "fill": rgba(TvTokens.color.focus.fill)},
        "disabled": {"fill": rgba(TvTokens.color.disabled.fill), "text": rgba(TvTokens.color.disabled.text)},
        "rating": {
          "imdb": rgba(TvTokens.color.rating.imdb),
          "tmdb": rgba(TvTokens.color.rating.tmdb),
          "rtFresh": rgba(TvTokens.color.rating.rtFresh),
          "rtRotten": rgba(TvTokens.color.rating.rtRotten),
          "audience": rgba(TvTokens.color.rating.audience),
          "plexCritic": rgba(TvTokens.color.rating.plexCritic),
        },
        "status": {
          "watched": rgba(TvTokens.color.status.watched),
          "progressTrack": rgba(TvTokens.color.status.progressTrack),
          "progressFill": rgba(TvTokens.color.status.progressFill),
          "unwatchedBadge": rgba(TvTokens.color.status.unwatchedBadge),
          "error": rgba(TvTokens.color.status.error),
          "onServer": rgba(TvTokens.color.status.onServer),
        },
      },
      "font": {
        "family": TvTokens.font.family,
        "fallback": [TvTokens.font.fallback[0], TvTokens.font.fallback[1]],
        "weights": {
          "regular": TvTokens.font.weights.regular,
          "medium": TvTokens.font.weights.medium,
          "semibold": TvTokens.font.weights.semibold,
          "bold": TvTokens.font.weights.bold,
          "extrabold": TvTokens.font.weights.extrabold,
        },
      },
      "type": {
        "display": {
          "size": TvTokens.type.display.size,
          "lineHeight": TvTokens.type.display.lineHeight,
          "weight": TvTokens.type.display.weight,
          "use": TvTokens.type.display.usage,
        },
        "headline": {
          "size": TvTokens.type.headline.size,
          "lineHeight": TvTokens.type.headline.lineHeight,
          "weight": TvTokens.type.headline.weight,
          "use": TvTokens.type.headline.usage,
        },
        "title": {
          "size": TvTokens.type.title.size,
          "lineHeight": TvTokens.type.title.lineHeight,
          "weight": TvTokens.type.title.weight,
          "use": TvTokens.type.title.usage,
        },
        "bodyLarge": {
          "size": TvTokens.type.bodyLarge.size,
          "lineHeight": TvTokens.type.bodyLarge.lineHeight,
          "weight": TvTokens.type.bodyLarge.weight,
          "use": TvTokens.type.bodyLarge.usage,
        },
        "body": {
          "size": TvTokens.type.body.size,
          "lineHeight": TvTokens.type.body.lineHeight,
          "weight": TvTokens.type.body.weight,
          "use": TvTokens.type.body.usage,
        },
        "label": {
          "size": TvTokens.type.label.size,
          "lineHeight": TvTokens.type.label.lineHeight,
          "weight": TvTokens.type.label.weight,
          "use": TvTokens.type.label.usage,
        },
        "caption": {
          "size": TvTokens.type.caption.size,
          "lineHeight": TvTokens.type.caption.lineHeight,
          "weight": TvTokens.type.caption.weight,
          "use": TvTokens.type.caption.usage,
        },
        "badge": {
          "size": TvTokens.type.badge.size,
          "lineHeight": TvTokens.type.badge.lineHeight,
          "weight": TvTokens.type.badge.weight,
          "use": TvTokens.type.badge.usage,
        },
      },
      "space": {
        "xxs": TvTokens.space.xxs,
        "xs": TvTokens.space.xs,
        "sm": TvTokens.space.sm,
        "md": TvTokens.space.md,
        "lg": TvTokens.space.lg,
        "xl": TvTokens.space.xl,
        "xxl": TvTokens.space.xxl,
        "xxxl": TvTokens.space.xxxl,
        "safeX": TvTokens.space.safeX,
        "safeY": TvTokens.space.safeY,
        "rowGap": TvTokens.space.rowGap,
        "cardGap": TvTokens.space.cardGap,
        "rowHeaderToCards": TvTokens.space.rowHeaderToCards,
        "contentLeft": TvTokens.space.contentLeft,
        "actionsGap": TvTokens.space.actionsGap,
      },
      "radius": {
        "xs": TvTokens.radius.xs,
        "sm": TvTokens.radius.sm,
        "card": TvTokens.radius.card,
        "button": TvTokens.radius.button,
        "iconButton": TvTokens.radius.iconButton,
        "chip": TvTokens.radius.chip,
        "panel": TvTokens.radius.panel,
        "badge": TvTokens.radius.badge,
      },
      "size": {
        "poster": {
          "w": TvTokens.size.poster.w,
          "h": TvTokens.size.poster.h,
          "ratio": TvTokens.size.poster.ratio,
          "perRowVisible": TvTokens.size.poster.perRowVisible,
        },
        "posterGrid": {
          "w": TvTokens.size.posterGrid.w,
          "h": TvTokens.size.posterGrid.h,
          "columns": TvTokens.size.posterGrid.columns,
          "gap": TvTokens.size.posterGrid.gap,
        },
        "episode": {
          "w": TvTokens.size.episode.w,
          "h": TvTokens.size.episode.h,
          "ratio": TvTokens.size.episode.ratio,
          "perRowVisible": TvTokens.size.episode.perRowVisible,
        },
        "seasonPoster": {"w": TvTokens.size.seasonPoster.w, "h": TvTokens.size.seasonPoster.h},
        "castAvatar": {"d": TvTokens.size.castAvatar.d},
        "button": {
          "h": TvTokens.size.button.h,
          "minW": TvTokens.size.button.minW,
          "padX": TvTokens.size.button.padX,
          "iconSize": TvTokens.size.button.iconSize,
          "iconGap": TvTokens.size.button.iconGap,
        },
        "iconButton": {
          "w": TvTokens.size.iconButton.w,
          "h": TvTokens.size.iconButton.h,
          "iconSize": TvTokens.size.iconButton.iconSize,
        },
        "chip": {"h": TvTokens.size.chip.h, "padX": TvTokens.size.chip.padX},
        "tab": {"h": TvTokens.size.tab.h, "padX": TvTokens.size.tab.padX, "underline": TvTokens.size.tab.underline},
        "sidebar": {
          "collapsedW": TvTokens.size.sidebar.collapsedW,
          "expandedW": TvTokens.size.sidebar.expandedW,
          "padLeft": TvTokens.size.sidebar.padLeft,
          "itemW": TvTokens.size.sidebar.itemW,
          "itemH": TvTokens.size.sidebar.itemH,
          "iconSize": TvTokens.size.sidebar.iconSize,
          "currentMarker": [TvTokens.size.sidebar.currentMarker[0], TvTokens.size.sidebar.currentMarker[1]],
        },
        "settingsItem": {
          "h": TvTokens.size.settingsItem.h,
          "iconSize": TvTokens.size.settingsItem.iconSize,
          "maxW": TvTokens.size.settingsItem.maxW,
        },
        "progressBar": {"h": TvTokens.size.progressBar.h},
        "unwatchedBadge": {"minW": TvTokens.size.unwatchedBadge.minW, "h": TvTokens.size.unwatchedBadge.h},
        "hero": {
          "h": TvTokens.size.hero.h,
          "compactH": TvTokens.size.hero.compactH,
          "textMaxW": TvTokens.size.hero.textMaxW,
          "logoMaxW": TvTokens.size.hero.logoMaxW,
          "logoMaxH": TvTokens.size.hero.logoMaxH,
        },
        "focusRing": {"width": TvTokens.size.focusRing.width, "offset": TvTokens.size.focusRing.offset},
        "letters": {
          "w": TvTokens.size.letters.w,
          "itemH": TvTokens.size.letters.itemH,
          "focusedH": TvTokens.size.letters.focusedH,
          "x": TvTokens.size.letters.x,
        },
        "keyboard": {
          "key": TvTokens.size.keyboard.key,
          "gap": TvTokens.size.keyboard.gap,
          "columns": TvTokens.size.keyboard.columns,
          "panelW": TvTokens.size.keyboard.panelW,
          "panelX": TvTokens.size.keyboard.panelX,
          "resultsX": TvTokens.size.keyboard.resultsX,
        },
        "buttonSmall": {"h": TvTokens.size.buttonSmall.h, "padX": TvTokens.size.buttonSmall.padX},
      },
      "focus": {
        "cardScale": TvTokens.focus.cardScale,
        "buttonScale": TvTokens.focus.buttonScale,
        "listItemScale": TvTokens.focus.listItemScale,
        "pressedScale": TvTokens.focus.pressedScale,
        "unfocusedSiblingOpacity": TvTokens.focus.unfocusedSiblingOpacity,
        "disabledOpacity": TvTokens.focus.disabledOpacity,
        "episodeScale": TvTokens.focus.episodeScale,
      },
      "motion": {
        "focusIn": TvTokens.motion.focusIn,
        "focusOut": TvTokens.motion.focusOut,
        "press": TvTokens.motion.press,
        "rowScroll": TvTokens.motion.rowScroll,
        "bgTintCrossfade": TvTokens.motion.bgTintCrossfade,
        "heroCrossfade": TvTokens.motion.heroCrossfade,
        "heroDebounce": TvTokens.motion.heroDebounce,
        "sidebarExpand": TvTokens.motion.sidebarExpand,
        "curve": TvTokens.motion.curve,
      },
      "player": {
        "autoHide": pl.autoHide,
        "panelFade": pl.panelFade,
        "pausedIndicatorHide": pl.pausedIndicatorHide,
        "focusResetAfter": pl.focusResetAfter,
        "seekSteps": pl.seekSteps,
        "seekAccelEvery": pl.seekAccelEvery,
        "seekCommitDelay": pl.seekCommitDelay,
        "skipButtonHide": pl.skipButtonHide,
        "upNextCountdown": pl.upNextCountdown,
        "upNextBeforeEnd": pl.upNextBeforeEnd,
        "shadeTop": {"h": pl.shadeTop.h, "from": rgba(pl.shadeTop.from), "to": rgba(pl.shadeTop.to)},
        "shadeBottom": {"h": pl.shadeBottom.h, "stops": pl.shadeBottom.stops.map(rgba).toList()},
        "bar": {
          "x": pl.bar.x,
          "w": pl.bar.w,
          "y": pl.bar.y,
          "h": pl.bar.h,
          "focusedH": pl.bar.focusedH,
          "track": rgba(pl.bar.track),
          "buffered": rgba(pl.bar.buffered),
          "seekRange": rgba(pl.bar.seekRange),
          "thumb": pl.bar.thumb,
          "chapterTick": pl.bar.chapterTick,
        },
        "controls": {
          "playX": pl.controls.playX,
          "rowY": pl.controls.rowY,
          "iconsY": pl.controls.iconsY,
          "iconsX": pl.controls.iconsX,
          "elapsedX": pl.controls.elapsedX,
          "hintY": pl.controls.hintY,
        },
        "seekPreview": {"w": pl.seekPreview.w, "h": pl.seekPreview.h, "bubbleH": pl.seekPreview.bubbleH},
        "rightPanel": {
          "w": pl.rightPanel.w,
          "bg": rgba(pl.rightPanel.bg),
          "padTop": pl.rightPanel.padTop,
          "padLeft": pl.rightPanel.padLeft,
          "padRight": pl.rightPanel.padRight,
          "itemMinH": pl.rightPanel.itemMinH,
        },
        "miniPause": {"h": pl.miniPause.h, "bg": rgba(pl.miniPause.bg)},
        "upNextCard": {
          "w": pl.upNextCard.w,
          "thumbW": pl.upNextCard.thumbW,
          "thumbH": pl.upNextCard.thumbH,
          "bg": rgba(pl.upNextCard.bg),
          "radius": pl.upNextCard.radius,
        },
        "subtitles": {
          "size": pl.subtitles.size,
          "lineHeight": pl.subtitles.lineHeight,
          "bottom": pl.subtitles.bottom,
          "outline": rgba(pl.subtitles.outline),
        },
      },
    };
    expect(actual, source);
    expect(TvTokens.color.bg.tintStrength, 0.44);
  });
}
