import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/screen_links/screen_link.dart';
import 'package:plezy/plezytv/screen_links/screen_link_queue.dart';

void main() {
  test('every target parses, including IDs, server and encoded search', () {
    for (final target in ScreenTarget.values.where((t) => t != ScreenTarget.libraryFilter)) {
      final link = ScreenLink.parse('plezytv://screen/${target.name}?id=42&server=machine&q=hello%20world');
      expect(link.target, target);
      expect(link.id, '42');
      expect(link.server, 'machine');
      expect(link.query, 'hello world');
    }
    expect(ScreenLink.parse('plezytv://screen/search').query, isNull);
    expect(ScreenLink.parse('plezytv://screen/item?id=1').server, isNull);
  });

  test('library-filter has an explicit path and exclusive required parameters', () {
    final link = ScreenLink.parse('plezytv://screen/library-filter?id=42&field=genre&value=1');
    expect(link.target, ScreenTarget.libraryFilter);
    expect(link.field, 'genre');
    expect(link.value, '1');
    for (final uri in [
      'library-filter?id=42&value=1',
      'library-filter?id=42&field=genre',
      'library-filter?field=genre&value=1',
      'libraryFilter?id=42&field=genre&value=1',
      'library-filter?id=42&field=genre&value=',
      'library-filter?id=abc&field=genre&value=1',
      'library-filter?id=42&field=genre&value=1&q=x',
      for (final target in ScreenTarget.values.where((t) => t != ScreenTarget.libraryFilter))
        '${target.name}?id=42&field=genre&value=1',
    ]) {
      expect(() => ScreenLink.parse('plezytv://screen/$uri'), throwsFormatException, reason: uri);
    }
  });

  test('invalid input and missing or ambiguous parameters fail', () {
    for (final source in [
      'garbage',
      'plezy://screen/home',
      'plezytv://screen/foo',
      'plezytv://screen',
      'plezytv://screen/home/extra',
      'plezytv://screen/item',
      'plezytv://screen/library?id=',
      'plezytv://screen/item?id=1&server=',
      'plezytv://screen/search?q=a&q=b',
      'plezytv://screen/home?unknown=1',
      'plezytv://screen/home#fragment',
      'plezytv://user@screen/home',
    ]) {
      expect(() => ScreenLink.parse(source), throwsFormatException, reason: source);
    }
  });

  test('injected metadata path is rejected once before dispatch', () async {
    final warnings = <String>[];
    var requests = 0;
    final queue = ScreenLinkQueue(
      isReady: () => true,
      dispatch: (_, _) async {
        requests++;
      },
      warn: (_, reason) => warnings.add(reason),
    );
    addTearDown(queue.dispose);
    queue.claim(
      'plezytv://screen/item?id=..%2F..%2F%3A%2Fscrobble%3Fkey%3D123%26identifier%3Dcom.plexapp.plugins.library',
    );
    await queue.flush();
    expect(requests, 0);
    expect(warnings, hasLength(1));
    for (final id in ['-1', ' 1', '1/2', '1?x=2', '1\n']) {
      expect(
        () => ScreenLink.parse('plezytv://screen/library?id=${Uri.encodeQueryComponent(id)}'),
        throwsFormatException,
      );
    }
    expect(() => ScreenLink.parse('plezytv://screen/item?id=1&server=..%2Fa'), throwsFormatException);
    expect(ScreenLink.parse('plezytv://screen/item?id=1&server=abc-123').server, 'abc-123');
  });

  test('play, live, original scheme and shelf IDs are not claimed', () {
    for (final source in [
      'plezytv://play?content_id=plezy_a_1',
      'plezytv://live?channel=4.1',
      'plezy://screen/settings',
      'plezy_server_42',
    ]) {
      expect(ScreenLink.claims(source), isFalse);
    }
  });

  test('latest waits indefinitely; invalid links log once; pass-through is untouched', () async {
    var ready = false;
    final applied = <ScreenTarget>[];
    final warnings = <String>[];
    final queue = ScreenLinkQueue(
      isReady: () => ready,
      dispatch: (link, current) async {
        applied.add(link.target);
      },
      warn: (link, reason) => warnings.add('$link: $reason'),
    );
    addTearDown(queue.dispose);
    queue.claim('plezytv://screen/home');
    queue.claim('plezytv://screen/settings');
    await queue.flush();
    expect(applied, isEmpty);
    expect(queue.claim('plezytv://live?channel=4.1'), isFalse);
    ready = true;
    await queue.flush();
    await queue.flush();
    expect(applied, [ScreenTarget.settings]);
    queue.claim('plezytv://screen/foo');
    await queue.flush();
    expect(warnings.single, contains('unknown target foo'));
  });

  test('not-ready server resolution is retried and superseded async work cannot act', () async {
    var connected = false;
    final applied = <ScreenTarget>[];
    final gate = Completer<void>();
    final queue = ScreenLinkQueue(
      isReady: () => true,
      dispatch: (link, current) async {
        if (!connected) throw const ScreenLinkNotReady();
        if (link.target == ScreenTarget.item) await gate.future;
        if (current()) applied.add(link.target);
      },
      warn: (_, reason) => fail(reason),
    );
    addTearDown(queue.dispose);
    queue.claim('plezytv://screen/item?id=1');
    await Future<void>.delayed(Duration.zero);
    connected = true;
    final first = queue.flush();
    queue.claim('plezytv://screen/settings');
    gate.complete();
    await first;
    await queue.flush();
    expect(applied, [ScreenTarget.settings]);
  });
}
