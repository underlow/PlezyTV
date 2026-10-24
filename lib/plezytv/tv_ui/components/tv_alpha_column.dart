import 'package:flutter/material.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

class TvAlphaLetter {
  const TvAlphaLetter(this.label, {this.empty = false});
  final String label;
  final bool empty;
}

/// Selection highlight belongs to the grid, independently of D-pad focus.
class TvAlphaColumn extends StatefulWidget {
  const TvAlphaColumn({
    super.key,
    required this.letters,
    required this.highlighted,
    required this.onSelect,
    required this.onLeft,
  });
  final List<TvAlphaLetter> letters;
  final String? highlighted;
  final ValueChanged<String> onSelect;
  final VoidCallback onLeft;
  @override
  State<TvAlphaColumn> createState() => TvAlphaColumnState();
}

class TvAlphaColumnState extends State<TvAlphaColumn> {
  final _nodes = <String, FocusNode>{};
  String? _frozen;
  bool _inside = false;
  void requestFocus() {
    final available = widget.letters.where((l) => !l.empty).toList();
    if (available.isEmpty) return;
    final label = available.any((l) => l.label == widget.highlighted) ? widget.highlighted! : available.first.label;
    _nodes[label]?.requestFocus();
  }

  void _move(int index, int step) {
    for (var i = index + step; i >= 0 && i < widget.letters.length; i += step) {
      if (!widget.letters[i].empty) {
        _nodes[widget.letters[i].label]?.requestFocus();
        return;
      }
    }
  }

  @override
  void didUpdateWidget(TvAlphaColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final labels = widget.letters.map((l) => l.label).toSet();
    for (final label in _nodes.keys.toList()) {
      if (!labels.contains(label)) _nodes.remove(label)!.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (inside) => setState(() {
      if (inside && !_inside) _frozen = widget.highlighted;
      _inside = inside;
    }),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.letters.length; i++)
          TvFocusable(
            focusNode: _nodes.putIfAbsent(
              widget.letters[i].label,
              () => FocusNode(debugLabel: 'TV letter ${widget.letters[i].label}'),
            ),
            disabled: widget.letters[i].empty,
            kind: TvFocusKind.outline,
            onNavigateUp: () => _move(i, -1),
            onNavigateDown: () => _move(i, 1),
            onNavigateLeft: widget.onLeft,
            onSelect: () => widget.onSelect(widget.letters[i].label),
            builder: (context, _) => SizedBox(
              width: TvTheme.of(context).px(40),
              child: Center(
                child: Text(
                  widget.letters[i].label,
                  style: TvTheme.of(context).caption.copyWith(
                    color: widget.letters[i].label == (_inside ? _frozen : widget.highlighted)
                        ? TvTokens.color.accent.normal
                        : TvTokens.color.text.secondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
