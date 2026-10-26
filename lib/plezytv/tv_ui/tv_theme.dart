import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import 'tv_tokens.dart';

/// Opt-in TV design scope. No screen is opted in automatically.
class TvTheme extends StatelessWidget {
  const TvTheme({super.key, required this.child});

  final Widget child;

  static TvThemeData of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_TvThemeScope>()!.data;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final data = TvThemeData(math.min(media.size.width / 1920, media.size.height / 1080));
    final parent = Theme.of(context);
    final base = monoTheme(MonoPalette.dark);
    final theme = parent.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TvTokens.color.bg.base,
      colorScheme: ColorScheme.dark(
        primary: TvTokens.color.accent.normal,
        onPrimary: TvTokens.color.text.onAccent,
        surface: TvTokens.color.surface.level1,
        onSurface: TvTokens.color.text.primary,
        error: TvTokens.color.status.error,
      ),
      textTheme: TextTheme(
        displayLarge: data.display,
        headlineLarge: data.headline,
        titleLarge: data.title,
        bodyLarge: data.bodyLarge,
        bodyMedium: data.body,
        labelLarge: data.label,
        bodySmall: data.caption,
        labelSmall: data.badge,
      ),
      extensions: [
        ...parent.extensions.values.where((extension) => extension is! MonoTokens),
        parent.extension<MonoTokens>() ?? base.extension<MonoTokens>()!,
      ],
    );
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.noScaling),
      child: Theme(
        data: theme,
        child: _TvThemeScope(data: data, child: child),
      ),
    );
  }
}

/// Scaled text styles and conversion shared by every descendant component.
class TvThemeData {
  const TvThemeData(this.scale);

  final double scale;
  double px(num designPixels) => designPixels * scale;

  TextStyle _style(({int size, int lineHeight, int weight, String usage}) token) => TextStyle(
    fontFamily: TvTokens.font.family,
    fontFamilyFallback: TvTokens.font.fallback,
    fontSize: px(token.size),
    height: token.lineHeight / token.size,
    fontWeight: FontWeight.values[token.weight ~/ 100 - 1],
    fontVariations: [FontVariation('wght', token.weight.toDouble())],
    color: TvTokens.color.text.primary,
  );

  TextStyle get display => _style(TvTokens.type.display);
  TextStyle get headline => _style(TvTokens.type.headline);
  TextStyle get title => _style(TvTokens.type.title);
  TextStyle get bodyLarge => _style(TvTokens.type.bodyLarge);
  TextStyle get body => _style(TvTokens.type.body);
  TextStyle get label => _style(TvTokens.type.label);
  TextStyle get caption => _style(TvTokens.type.caption);
  TextStyle get badge => _style(TvTokens.type.badge);
}

class _TvThemeScope extends InheritedWidget {
  const _TvThemeScope({required this.data, required super.child});
  final TvThemeData data;

  @override
  bool updateShouldNotify(_TvThemeScope oldWidget) => data.scale != oldWidget.data.scale;
}

/// Card art plus the two rounded caption line boxes (S24 R2a).
double tvCardHeight(BuildContext context, num artHeight) {
  final theme = TvTheme.of(context);
  return artHeight +
      20 +
      (theme.px(TvTokens.type.body.lineHeight).ceilToDouble() +
              theme.px(TvTokens.type.caption.lineHeight).ceilToDouble()) /
          theme.scale;
}
