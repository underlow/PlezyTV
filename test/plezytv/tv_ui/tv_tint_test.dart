import 'dart:async';
import 'package:drift/native.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_server_client.dart';
import '../../test_helpers/backend_client_fixtures.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/tv_tint_service.dart';
import 'package:plezy/plezytv/tv_ui/tv_tinted_background.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';

import 'tv_theme_test_helper.dart';

class _ArtworkClient implements MediaServerClient {
  final plex = testPlexClient();
  final urls = <Uri>[];
  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) {
    urls.add(Uri.parse(plex.thumbnailUrl(path, width: width, height: height, cover: cover)));
    return ''; // Stop before transport; exercise the production URL builder.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TvArtworkSource source(String id, {String server = 'server'}) => TvArtworkSource(
  item: MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, serverId: server),
);

Uint8List pixels(Color color, [int count = 100]) => Uint8List.fromList(
  List.generate(
    count,
    (_) => [(color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round(), 255],
  ).expand((p) => p).toList(),
);

Future<ui.Image> image(Color color, {int width = 64, int height = 96}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

class StubTintService extends TvTintService {
  StubTintService({super.fetch, super.decode});
  final requests = <String>[];
  final answers = <String, Completer<Color?>>{};
  @override
  Future<Color?> tintFor(TvArtworkSource source) {
    requests.add(source.item.id);
    return (answers[source.item.id] ??= Completer<Color?>()).future;
  }
}

List<Color> gradientTops(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((w) => w.decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.gradient)
    .whereType<LinearGradient>()
    .where((g) => g.stops?.contains(.85) ?? false)
    .map((g) => g.colors.first)
    .toList();

void main() {
  test('S24 Plex backdrop and tint URLs supply both transcode dimensions', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(database);
    addTearDown(database.close);
    final client = _ArtworkClient();
    addTearDown(client.plex.close);
    final artwork = TvArtworkSource(
      item: source('url').item.copyWith(artPath: '/art', thumbPath: '/poster'),
      client: client,
    );
    await fetchTvArtwork(artwork, true, 1280);
    await fetchTvArtwork(artwork, false, 64);
    expect(client.urls.map((url) => (url.queryParameters['width'], url.queryParameters['height'])), [
      ('1280', '720'),
      ('64', '64'),
    ]);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('A6/A6c dominant colors clamp and maintain text contrast; neutrals ignored', () {
    for (final color in [Colors.red, Colors.yellow, Colors.white]) {
      final value = dominantTvTint(pixels(color));
      final tint = value == null ? null : Color(value);
      if (color == Colors.white) {
        expect(tint, isNull);
      } else {
        final hsl = HSLColor.fromColor(tint!);
        expect(hsl.saturation, lessThanOrEqualTo(.45));
        expect(hsl.lightness, inInclusiveRange(.10, .18));
      }
      final ratio =
          (TvTokens.color.text.primary.computeLuminance() + .05) / (tvBackgroundTop(tint).computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
    expect(dominantTvTint(Uint8List.fromList([...pixels(Colors.black), ...pixels(Colors.grey)])), isNull);
    expect(
      HSLColor.fromColor(
        Color(
          dominantTvTint(
            Uint8List.fromList([...pixels(Colors.red), ...pixels(Colors.blue, 10), ...pixels(Colors.grey, 200)]),
          )!,
        ),
      ).hue,
      closeTo(4.5, 2),
    );
  });

  test('service fetch/decode width, worker analysis, concurrent cache, failure, LRU and server key', () async {
    var fetches = 0;
    final service = TvTintService(
      capacity: 2,
      fetch: (source, backdrop, width) async {
        fetches++;
        expect(width, 64);
        expect(backdrop, false);
        if (source.item.id == 'bad') throw StateError('fetch failed');
        return Uint8List(1);
      },
      decode: (bytes, width) {
        expect(width, 64);
        return image(Colors.red);
      },
    );
    final a = service.tintFor(source('a'));
    final duplicate = service.tintFor(source('a'));
    expect(await a, await duplicate);
    expect(await service.tintFor(source('a')), isNotNull);
    expect(fetches, 1);
    expect(await service.tintFor(source('bad')), isNull);
    expect(await service.tintFor(source('bad')), isNull);
    expect(fetches, 2);
    await service.tintFor(source('a', server: 'other'));
    expect(fetches, 3);
    await service.tintFor(source('a'));
    expect(fetches, 4);
  });

  test('local/offline artwork and actual decode width cap', () async {
    final directory = await Directory.systemTemp.createTemp('tv-tint-test-');
    try {
      final original = await image(Colors.yellow, width: 1600, height: 900);
      final png = await original.toByteData(format: ui.ImageByteFormat.png);
      original.dispose();
      final file = File('${directory.path}/poster.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      final local = TvArtworkSource(
        item: source('local').item,
        offline: true,
        localPosterPath: file.path,
        localBackdropPath: file.path,
      );
      final bytes = await fetchTvArtwork(local, false, 64);
      expect(bytes, isNotNull);
      final decoded = await decodeTvArtwork(bytes!, 1280);
      expect(decoded.width, 1280);
      expect(decoded.height, 720);
      decoded.dispose();
      expect(await TvTintService().tintFor(local), isNotNull);
      final missing = TvArtworkSource(
        item: source('missing').item,
        offline: true,
        localPosterPath: '${directory.path}/missing',
      );
      expect(await fetchTvArtwork(missing, false, 64), isNull);
      expect(await fetchTvArtwork(missing, true, 1280), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  for (final removeWidget in [false, true]) {
    testWidgets('pending backdrop released immediately on ${removeWidget ? 'dispose' : 'source change'}', (
      tester,
    ) async {
      final decoded = await tester.runAsync(() => image(Colors.red));
      var disposals = 0;
      final oldOnDispose = ui.Image.onDispose;
      ui.Image.onDispose = (value) {
        if (identical(value, decoded)) disposals++;
        oldOnDispose?.call(value);
      };
      addTearDown(() => ui.Image.onDispose = oldOnDispose);
      final service = StubTintService(fetch: (_, _, _) async => Uint8List(1), decode: (_, _) async => decoded!);
      final current = ValueNotifier(source('A'));
      addTearDown(current.dispose);
      await pumpTvWidget(
        tester,
        ValueListenableBuilder<TvArtworkSource>(
          valueListenable: current,
          builder: (_, value, _) => TvTintedBackground(source: value, service: service),
        ),
      );
      await tester.pump();
      expect(decoded!.debugDisposed, isFalse);
      expect(service.answers['A']!.isCompleted, isFalse);
      if (removeWidget) {
        await tester.pumpWidget(const SizedBox());
      } else {
        current.value = source('B');
        await tester.pump();
      }
      expect(decoded.debugDisposed, isTrue);
      expect(disposals, 1);
      service.answers['A']!.complete(Colors.red);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(disposals, 1);
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('30 interrupted fades keep layers and live images bounded', (tester) async {
    final decoded = <ui.Image>[];
    final template = await tester.runAsync(() => image(Colors.red, width: 1280, height: 1));
    final service = StubTintService(
      fetch: (_, _, _) async => Uint8List(1),
      decode: (_, _) async {
        final result = template!.clone();
        decoded.add(result);
        return result;
      },
    );
    final current = ValueNotifier(source('0'));
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (_, value, _) => TvTintedBackground(source: value, service: service),
      ),
    );
    service.answers['0']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    for (var i = 1; i <= 30; i++) {
      current.value = source('$i');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      service.answers['$i']!.complete(Colors.blue);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(Opacity).evaluate().length, lessThanOrEqualTo(3));
      expect(find.byType(RawImage).evaluate().length, lessThanOrEqualTo(3));
      expect(decoded.where((image) => !image.debugDisposed).length, lessThanOrEqualTo(3));
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    expect(decoded.where((image) => !image.debugDisposed).length, 1);
    await tester.pumpWidget(const SizedBox());
    expect(decoded.every((image) => image.debugDisposed), isTrue);
    current.dispose();
    template!.dispose();
  });

  testWidgets('stale asynchronous result cannot replace the current item', (tester) async {
    final service = StubTintService();
    final current = ValueNotifier(source('A'));
    addTearDown(current.dispose);
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (context, value, _) => TvTintedBackground(source: value, service: service, showBackdrop: false),
      ),
    );
    current.value = source('B');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    service.answers['B']!.complete(Colors.blue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 401));
    service.answers['A']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    expect(gradientTops(tester), [tvBackgroundTop(Colors.blue)]);
    expect(tester.hasRunningAnimations, false);
  });

  testWidgets('plain background has a subtle cool top and base at 85 percent', (tester) async {
    await pumpTvWidget(tester, const TvPlainBackground());
    final top = gradientTops(tester).single;
    expect(top.b, greaterThan(top.r));
    expect(top, isNot(TvTokens.color.bg.base));
    expect(tester.hasRunningAnimations, false);
  });

  testWidgets('A6b first display instant, B never fetched, C debounces and fades for 400ms', (tester) async {
    final service = StubTintService();
    final current = ValueNotifier(source('A'));
    addTearDown(current.dispose);
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (context, value, _) => TvTintedBackground(source: value, service: service, showBackdrop: false),
      ),
    );
    service.answers['A']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, false);
    expect(gradientTops(tester), [tvBackgroundTop(Colors.red)]);
    current.value = source('B');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    current.value = source('C');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(service.requests, ['A']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.requests, ['A', 'C']);
    service.answers['C']!.complete(Colors.blue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, true);
    expect(tester.widgetList<Opacity>(find.byType(Opacity)).last.opacity, closeTo(.5, .01));
    await tester.pump(const Duration(milliseconds: 200));
    final remainingLayers = tester.widgetList<Opacity>(find.byType(Opacity));
    if (remainingLayers.isNotEmpty) {
      expect(remainingLayers.last.opacity, closeTo(1, 1e-9));
    }
    // Ticker elapsed seconds can land just below 0.4 due to double rounding.
    await tester.pump(const Duration(microseconds: 1));
    expect(tester.hasRunningAnimations, false);
    expect(gradientTops(tester), [tvBackgroundTop(Colors.blue)]);
  });

  testWidgets('no tint and failed backdrop give only base gradient; backdrop decode capped', (tester) async {
    final widths = <int>[];
    final service = StubTintService(
      fetch: (_, backdrop, width) async {
        expect(backdrop, true);
        expect(width, 1280);
        return Uint8List(1);
      },
      decode: (_, width) async {
        widths.add(width);
        throw StateError('decode failed');
      },
    );
    await pumpTvWidget(tester, TvTintedBackground(source: source('A'), service: service));
    service.answers['A']!.complete(null);
    await tester.pump();
    await tester.pump();
    expect(widths, [1280]);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    expect(gradientTops(tester), [TvTokens.color.bg.base]);
  });

  testWidgets('interrupted crossfade freezes the current composite', (tester) async {
    final service = StubTintService();
    final current = ValueNotifier(source('A'));
    addTearDown(current.dispose);
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (context, value, _) => TvTintedBackground(source: value, service: service, showBackdrop: false),
      ),
    );
    service.answers['A']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    current.value = source('B');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    service.answers['B']!.complete(Colors.blue);
    await tester.pump();
    await tester.pump();
    current.value = source('C');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    service.answers['C']!.complete(Colors.green);
    await tester.pump();
    await tester.pump();
    expect(gradientTops(tester), [
      tvBackgroundTop(Colors.red),
      tvBackgroundTop(Colors.blue),
      tvBackgroundTop(Colors.green),
    ]);
    expect(tester.widgetList<Opacity>(find.byType(Opacity)).first.opacity, closeTo(.75, .01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(gradientTops(tester), [tvBackgroundTop(Colors.green)]);
  });

  testWidgets('R17a scrolling fades only artwork linearly over 300 design pixels', (tester) async {
    final page = ScrollController();
    addTearDown(page.dispose);
    final service = StubTintService(fetch: (_, _, _) async => Uint8List(1), decode: (_, _) => image(Colors.yellow));
    await pumpTvWidget(
      tester,
      TvTintedBackground(
        source: source('A'),
        service: service,
        scrollController: page,
        child: SingleChildScrollView(controller: page, child: const SizedBox(height: 2000)),
      ),
    );
    service.answers['A']!.complete(Colors.red);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    final masks = tester.widgetList<ShaderMask>(find.byType(ShaderMask)).toList();
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    final boundary = find.ancestor(of: find.byType(RawImage), matching: find.byType(RepaintBoundary)).first;
    expect(boundary, findsOneWidget);
    final paintBoundary = tester.renderObject<RenderRepaintBoundary>(boundary);
    paintBoundary.debugResetMetrics();
    FadeTransition? previousFade;
    for (final offset in [0.0, 150.0, 300.0, 400.0, 500.0]) {
      page.jumpTo(offset);
      await tester.pump();
      final opacity = tester.widget<FadeTransition>(
        find.ancestor(of: find.byType(RawImage), matching: find.byType(FadeTransition)).first,
      );
      expect(opacity.opacity.value, (1 - offset / 300).clamp(0, 1));
      expect(gradientTops(tester), [tvBackgroundTop(Colors.red)]);
      final currentMasks = tester.widgetList<ShaderMask>(find.byType(ShaderMask)).toList();
      for (var i = 0; i < masks.length; i++) {
        expect(currentMasks[i], same(masks[i]), reason: 'scroll must retain shader closures');
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)), same(raw));
      if (offset > 300) expect(opacity, same(previousFade), reason: 'saturated opacity must not rebuild');
      expect(paintBoundary.debugSymmetricPaintCount, 0, reason: 'opacity must retain the painted artwork layer');
      previousFade = opacity;
    }
  });

  testWidgets('slow backdrop does not delay tint or restart its fade', (tester) async {
    final pendingBackdrop = Completer<Uint8List?>();
    final service = StubTintService(
      fetch: (_, _, _) => pendingBackdrop.future,
      decode: (_, width) {
        expect(width, 1280);
        return image(Colors.yellow);
      },
    );
    final current = ValueNotifier(source('A'));
    addTearDown(current.dispose);
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (context, value, _) => TvTintedBackground(source: value, service: service),
      ),
    );
    service.answers['A']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    expect(gradientTops(tester), [tvBackgroundTop(Colors.red)]);
    current.value = source('B');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    service.answers['B']!.complete(Colors.blue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 401));
    expect(gradientTops(tester), [tvBackgroundTop(Colors.blue)]);
    expect(tester.hasRunningAnimations, false);
    // Both A and B awaited this fetch; A must dispose its stale decode.
    await tester.runAsync(() async {
      pendingBackdrop.complete(Uint8List(1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.hasRunningAnimations, false);
    expect(tester.getSize(find.byType(RawImage)), const Size(1300, 780));
    expect(tester.widget<RawImage>(find.byType(RawImage)).opacity!.value, .6);
    expect(
      tester
          .widget<ColoredBox>(find.ancestor(of: find.byType(RawImage), matching: find.byType(ColoredBox)).first)
          .color,
      TvTokens.color.bg.base,
    );
    // Rasterize the production shaders, checking R17 screen coordinates.
    final masks = tester.widgetList<ShaderMask>(find.byType(ShaderMask)).toList();
    const rect = Rect.fromLTWH(0, 0, 1300, 780);
    for (final (mask, points, expected, horizontal) in [
      (masks.last, [1000, 1250, 1500], [0.0, .5, 1.0], true),
      (masks.first, [360, 500, 640], [1.0, .5, 0.0], false),
    ]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(rect, Paint()..shader = mask.shaderCallback(rect));
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final raster = await picture.toImage(1300, 780);
        final bytes = (await raster.toByteData())!;
        for (var i = 0; i < points.length; i++) {
          final x = horizontal ? points[i] - 620 : 1000;
          final y = horizontal ? 100 : points[i];
          expect(
            bytes.getUint8((y * 1300 + x) * 4 + 3) / 255,
            closeTo(expected[i], .01),
            reason: 'R17 ${horizontal ? "x" : "y"}=${points[i]}',
          );
        }
        raster.dispose();
        picture.dispose();
      });
    }
  });

  testWidgets('reduced updates have no running animation', (tester) async {
    final service = StubTintService();
    final current = ValueNotifier(source('A'));
    addTearDown(current.dispose);
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: current,
        builder: (context, value, _) => TvTintedBackground(source: value, service: service, showBackdrop: false),
      ),
      reduced: true,
    );
    service.answers['A']!.complete(Colors.red);
    await tester.pump();
    await tester.pump();
    current.value = source('B');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    service.answers['B']!.complete(null);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, false);
    expect(gradientTops(tester), [TvTokens.color.bg.base]);
  });
}
