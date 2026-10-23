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
    this.onFocusInsideChanged,
  }) : assert(itemCount >= 0),
       assert(cardWidth > 0),
       assert(cardHeight > 0);

  final String title;
  final String? counter;
  final int itemCount;
  /// Full card layout size, including captions; headroom is added by the row.
  final double cardWidth, cardHeight;
  final Widget Function(BuildContext context, int index, FocusNode focusNode) cardBuilder;
  final ValueChanged<bool>? onFocusInsideChanged;

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

  /// Re-enter through the scope so Flutter restores its last focused child.
  void requestFocus() {
    if (widget.itemCount > 0) _scope.requestFocus();
  }

  @override
  void didUpdateWidget(TvHorizontalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount < oldWidget.itemCount) {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft && event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final step = event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1;
      var target = _index + step;
      while (target >= 0 && target < widget.itemCount) {
        final candidate = _memory.nodeFor('$target');
        if (candidate != null && candidate.context != null && candidate.canRequestFocus) {
          candidate.requestFocus();
          break;
        }
        target += step;
      }
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
    final left = px(TvTokens.space.contentLeft);
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
            SizedBox(height: px(16)),
            SizedBox(
              height: px(widget.cardHeight + 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.maxWidth - left;
                  return ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    clipBehavior: Clip.none,
                    scrollCacheExtent: ScrollCacheExtent.pixels(_viewport),
                    padding: EdgeInsets.only(left: left, top: px(24), right: _viewport),
                    itemExtent: _extent,
                    itemCount: widget.itemCount,
                    itemBuilder: (context, index) {
                      final node = _memory.get('$index');
                      return Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (focused) {
                          if (focused) {
                            _index = index;
                            _scrollTo(index);
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
