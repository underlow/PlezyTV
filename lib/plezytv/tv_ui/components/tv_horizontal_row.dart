import '../../../navigation/main_screen_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../focus/focus_memory_tracker.dart';
import '../../../services/device_performance.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// A lazy, fixed-slot rail. Dimensions are design pixels. The builder must
/// attach the supplied node to its card's focusable (with auto-scroll off).
class TvHorizontalRow extends StatefulWidget {
  const TvHorizontalRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.cardBuilder,
    required this.cardWidth,
    required this.cardHeight,
    this.counter,
    this.contentLeft,
    this.onFocusInsideChanged,
    this.itemKey,
    this.onItemFocused,
  }) : assert(itemCount >= 0),
       assert(cardWidth > 0),
       assert(cardHeight > 0);

  /// Design-pixel inset; use zero inside an already padded content area.
  final num? contentLeft;
  final String title;
  final String? counter;
  final int itemCount;

  /// Full card layout size, including captions; headroom is added by the row.
  final double cardWidth, cardHeight;
  final Widget Function(BuildContext context, int index, FocusNode focusNode) cardBuilder;
  final ValueChanged<bool>? onFocusInsideChanged;

  /// Stable identity, including server identity for media. Omit for index memory.
  final String Function(int index)? itemKey;
  final ValueChanged<int>? onItemFocused;

  @override
  State<TvHorizontalRow> createState() => TvHorizontalRowState();
}

class TvHorizontalRowState extends State<TvHorizontalRow> {
  final _scroll = ScrollController();
  final _scope = FocusScopeNode(debugLabel: 'TV row');
  final _inside = ValueNotifier(false);
  final _memory = FocusMemoryTracker();
  int _index = 0;
  bool _hasScrolled = false;
  double _extent = 0, _viewport = 0;

  ValueListenable<bool> get focusInside => _inside;

  String _key(int index) => widget.itemKey?.call(index) ?? '$index';
  int get focusedIndex => _index;

  /// Returns true if already at the start; otherwise moves there.
  bool focusStart() {
    if (_index == 0) return true;
    _index = 0;
    _seekPending = true;
    _seek(0, 1, ++_seekGeneration, _scroll.hasClients ? _scroll.offset : 0);
    return false;
  }

  /// Re-enter the remembered item, or an explicit stable [itemKey], revealing
  /// it if it left the lazy viewport.
  void requestFocus({String? itemKey}) {
    if (widget.itemCount == 0) return;
    if (itemKey != null) {
      for (var i = 0; i < widget.itemCount; i++) {
        if (_key(i) == itemKey) {
          _index = i;
          break;
        }
      }
    }
    if (widget.itemKey == null && _memory.lastFocusedKey != null) {
      _scope.requestFocus();
    } else {
      _seekPending = true;
      _seek(_index, 1, ++_seekGeneration, _scroll.hasClients ? _scroll.offset : 0);
    }
  }

  @override
  void didUpdateWidget(TvHorizontalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousKey = _index < oldWidget.itemCount ? oldWidget.itemKey?.call(_index) : null;
    final hadFocus = _scope.hasFocus;
    final previousFocus = FocusManager.instance.primaryFocus;
    final owners = {previousFocus, ...?previousFocus?.ancestors};
    if (widget.itemKey != null) {
      final keys = [for (var i = 0; i < widget.itemCount; i++) _key(i)];
      final same = keys.indexOf(previousKey ?? '');
      _index = same >= 0 ? same : _index.clamp(0, keys.isEmpty ? 0 : keys.length - 1);
      final restoreIndex = _index;
      final generation = ++_seekGeneration;
      _seekPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _seekGeneration) return;
        _memory.pruneExcept({for (var i = 0; i < widget.itemCount; i++) _key(i)});
        if (hadFocus &&
            widget.itemCount > 0 &&
            (FocusManager.instance.primaryFocus == null ||
                _scope.hasFocus ||
                owners.contains(FocusManager.instance.primaryFocus)) &&
            (ModalRoute.of(context)?.isCurrent ?? true) &&
            TickerMode.valuesOf(context).enabled) {
          _index = restoreIndex;
          widget.onItemFocused?.call(_index);
          requestFocus();
        }
      });
    } else if (widget.itemCount < oldWidget.itemCount) {
      _memory.pruneExcept({for (var i = 0; i < widget.itemCount; i++) '$i'});
      _index = _index.clamp(0, widget.itemCount > 0 ? widget.itemCount - 1 : 0);
    }
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final slots = ((_viewport + TvTheme.of(context).px(TvTokens.space.cardGap)) / _extent).floor();
    if (!_hasScrolled && index < slots) return;
    _hasScrolled = index != 0;
    final target = (index * _extent).clamp(0.0, _scroll.position.maxScrollExtent);
    // Shared TV scroll policy: change the reduced-tier choice here.
    if (DevicePerformance.isReduced) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: Duration(milliseconds: TvTokens.motion.rowScroll),
        curve: Curves.easeOutCubic,
      );
    }
  }

  int _seekGeneration = 0;
  bool _seekPending = false;

  void _seek(int target, int step, int generation, double originalOffset) {
    if (!mounted || generation != _seekGeneration) return;
    while (target >= 0 && target < widget.itemCount) {
      final candidate = _memory.nodeFor(_key(target));
      if (candidate == null || candidate.context?.mounted != true || !candidate.ancestors.contains(_scope)) {
        // Reveal one cache-sized region at a time rather than building the
        // entire disabled run. Retry after layout attaches its focus nodes.
        _scroll.jumpTo((target * _extent).clamp(0.0, _scroll.position.maxScrollExtent));
        final next = target;
        WidgetsBinding.instance.addPostFrameCallback((_) => _seek(next, step, generation, originalOffset));
        return;
      }
      if (candidate.canRequestFocus) {
        if (candidate.hasFocus) _scrollTo(target);
        candidate.requestFocus();
        _seekPending = false;
        return;
      }
      target += step;
    }
    // Reveal jumps are speculative: restore the exact viewport, bypassing the
    // initial-slot optimization and without changing the row scroll policy.
    _scroll.jumpTo(originalOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _seekGeneration) {
        _memory.nodeFor(_key(_index))?.requestFocus();
        _seekPending = false;
      }
    });
    // An edge seek may restore an unchanged offset, which schedules no layout.
    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft && event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _index == 0 && !_seekPending) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // Coalesce both directions until speculative reveals and any restoration
      // finish, so another key cannot capture a temporary viewport as its origin.
      if (_seekPending) return KeyEventResult.handled;
      _seekPending = true;
      final step = event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1;
      _seek(_index + step, step, ++_seekGeneration, _scroll.offset);
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _scope.dispose();
    _memory.dispose();
    _scroll.dispose();
    _inside.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final left =
        (widget.contentLeft == null
                ? px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)
                : px(widget.contentLeft!))
            .clamp(0.0, double.infinity);
    _extent = px(widget.cardWidth + TvTokens.space.cardGap);
    return FocusScope(
      node: _scope,
      onFocusChange: (value) {
        _inside.value = value;
        widget.onFocusInsideChanged?.call(value);
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: left),
              child: Row(
                children: [
                  Text(widget.title, style: theme.title),
                  if (widget.counter != null) ...[
                    SizedBox(width: px(16)),
                    Text(widget.counter!, style: theme.caption.copyWith(color: TvTokens.color.text.tertiary)),
                  ],
                ],
              ),
            ),
            SizedBox(height: px(TvTokens.space.rowHeaderToCards)),
            SizedBox(
              height: px(widget.cardHeight + TvTokens.space.cardFocusReserve),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.maxWidth - left;
                  return ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    clipBehavior: Clip.none,
                    scrollCacheExtent: ScrollCacheExtent.pixels(_viewport),
                    padding: EdgeInsets.only(left: left, top: px(TvTokens.space.cardFocusReserve), right: _viewport),
                    itemExtent: _extent,
                    itemCount: widget.itemCount,
                    findChildIndexCallback: widget.itemKey == null
                        ? null
                        : (key) {
                            for (var i = 0; i < widget.itemCount; i++) {
                              if (ValueKey(_key(i)) == key) return i;
                            }
                            return null;
                          },
                    itemBuilder: (context, index) {
                      final node = _memory.get(_key(index));
                      return Focus(
                        key: ValueKey(_key(index)),
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (focused) {
                          if (focused) {
                            _index = index;
                            _scrollTo(index);
                            widget.onItemFocused?.call(index);
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.only(right: px(TvTokens.space.cardGap)),
                          child: widget.cardBuilder(context, index, node),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
