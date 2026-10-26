import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/dpad_navigator.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// On-screen layouts of the search keyboard (S11 R2). [prefValue] is the value
/// stored in `plezytv_search_keyboard_layout`.
enum TvSearchKeyboardLayout {
  ru('ru', 'РУС'),
  en('en', 'ENG'),
  digits('digits', '123');

  const TvSearchKeyboardLayout(this.prefValue, this.label);

  final String prefValue;
  final String label;

  /// Unknown or missing values fall back to [ru].
  static TvSearchKeyboardLayout fromPref(String? value) =>
      values.firstWhere((layout) => layout.prefValue == value, orElse: () => ru);
}

abstract final class TvSearchKeyboardStrings {
  static const clear = 'Clear';
  static const space = 'Space';
  static const backspace = 'Backspace';
  static const toDigits = '0–9';
}

enum _KeyKind { char, space, backspace, clear, toDigits, layout }

@immutable
class _KeySpec {
  const _KeySpec(this.id, this.kind, {this.char, this.layout});

  final String id;
  final _KeyKind kind;
  final String? char;
  final TvSearchKeyboardLayout? layout;
}

/// One key placed on the grid: [col] is its first column, [span] its width in cells.
class _Placed {
  const _Placed(this.spec, this.row, this.col, this.span);
  final _KeySpec spec;
  final int row, col, span;
}

const _columns = 6;

_KeySpec _char(String c) => _KeySpec('char:$c', _KeyKind.char, char: c);

List<List<_KeySpec?>> _charRows(TvSearchKeyboardLayout layout) {
  List<_KeySpec?> chars(String s) => [for (final c in s.split('')) _char(c)];
  const toDigits = _KeySpec('toDigits', _KeyKind.toDigits);
  switch (layout) {
    case TvSearchKeyboardLayout.ru:
      return [
        chars('абвгде'),
        chars('ёжзийк'),
        chars('лмнопр'),
        chars('стуфхц'),
        chars('чшщъыь'),
        [...chars('эюя-'), toDigits],
      ];
    case TvSearchKeyboardLayout.en:
      return [
        chars('abcdef'),
        chars('ghijkl'),
        chars('mnopqr'),
        chars('stuvwx'),
        [...chars('yz-'), toDigits],
      ];
    case TvSearchKeyboardLayout.digits:
      return [chars('123456'), chars('7890.,'), chars("-_':!?"), chars('&@#()+')];
  }
}

List<_Placed> _buildGrid(TvSearchKeyboardLayout layout) {
  final placed = <_Placed>[];
  final rows = _charRows(layout);
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final spec = rows[r][c];
      if (spec != null) {
        placed.add(_Placed(spec, r, c, spec.kind == _KeyKind.toDigits ? _columns - c : 1));
      }
    }
  }
  var r = rows.length;
  placed
    ..add(_Placed(const _KeySpec('space', _KeyKind.space, char: ' '), r, 0, 2))
    ..add(_Placed(const _KeySpec('backspace', _KeyKind.backspace), r, 2, 2))
    ..add(_Placed(const _KeySpec('clear', _KeyKind.clear), r, 4, 2));
  r++;
  for (final (i, l) in TvSearchKeyboardLayout.values.indexed) {
    placed.add(_Placed(_KeySpec('layout:${l.prefValue}', _KeyKind.layout, layout: l), r, i * 2, 2));
  }
  return placed;
}

/// The S11 search keyboard. It holds no query: every key reports through the
/// callbacks, and the screen owns the text and the layout.
class TvSearchKeyboard extends StatefulWidget {
  const TvSearchKeyboard({
    super.key,
    required this.layout,
    required this.onLayoutChanged,
    required this.onInput,
    required this.onBackspace,
    required this.onClear,
    required this.onExitLeft,
    required this.onExitRight,
  });

  final TvSearchKeyboardLayout layout;
  final ValueChanged<TvSearchKeyboardLayout> onLayoutChanged;
  final ValueChanged<String> onInput;
  final VoidCallback onBackspace, onClear, onExitLeft;

  /// Returns whether focus left the keyboard; if not, focus stays on the key.
  final bool Function() onExitRight;

  @override
  State<TvSearchKeyboard> createState() => TvSearchKeyboardState();
}

class TvSearchKeyboardState extends State<TvSearchKeyboard> {
  final _root = FocusNode(debugLabel: 'TvSearchKeyboard', skipTraversal: true);
  final _nodes = <String, FocusNode>{};
  late List<_Placed> _grid = _buildGrid(widget.layout);
  String? _lastPressed;
  String? _focusedId;
  String? _pressedId;

  /// Column the user travels along vertically (kept across wide keys).
  int _cursorCol = 0;

  bool get hasFocus => _root.hasFocus;

  /// Focuses the last pressed key, or the first key of the current layout.
  void focusLastKey() {
    final last = _lastPressed;
    final placed = last == null ? null : _byId(last);
    _focus(placed ?? _grid.first);
  }

  void focusFirstKey() => _focus(_grid.first);

  FocusNode _node(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'key $id'));

  _Placed? _byId(String id) {
    for (final p in _grid) {
      if (p.spec.id == id) return p;
    }
    return null;
  }

  _Placed? _at(int row, int col) {
    for (final p in _grid) {
      if (p.row == row && col >= p.col && col < p.col + p.span) return p;
    }
    return null;
  }

  int get _rowCount => _grid.last.row + 1;

  void _focus(_Placed p, {int? cursorCol}) {
    _cursorCol = cursorCol ?? p.col;
    _node(p.spec.id).requestFocus();
  }

  @override
  void didUpdateWidget(TvSearchKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout == widget.layout) return;
    final hadFocus = hasFocus;
    final focused = _focusedId;
    _grid = _buildGrid(widget.layout);
    if (hadFocus && (focused == null || _byId(focused) == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusLastKey();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _root.dispose();
    super.dispose();
  }

  void _activate(_Placed p) {
    _lastPressed = p.spec.id;
    switch (p.spec.kind) {
      case _KeyKind.char:
      case _KeyKind.space:
        widget.onInput(p.spec.char!);
      case _KeyKind.backspace:
        widget.onBackspace();
      case _KeyKind.clear:
        widget.onClear();
      case _KeyKind.toDigits:
        _lastPressed = 'layout:${TvSearchKeyboardLayout.digits.prefValue}';
        if (widget.layout != TvSearchKeyboardLayout.digits) widget.onLayoutChanged(TvSearchKeyboardLayout.digits);
      case _KeyKind.layout:
        if (widget.layout != p.spec.layout) widget.onLayoutChanged(p.spec.layout!);
    }
  }

  void _moveHorizontal(_Placed from, int dir) {
    var col = dir > 0 ? from.col + from.span : from.col - 1;
    while (col >= 0 && col < _columns) {
      final target = _at(from.row, col);
      if (target != null) return _focus(target);
      col += dir;
    }
    if (dir < 0) {
      widget.onExitLeft();
    } else {
      widget.onExitRight();
    }
  }

  void _moveVertical(_Placed from, int dir) {
    final col = _cursorCol.clamp(from.col, from.col + from.span - 1);
    for (var row = from.row + dir; row >= 0 && row < _rowCount; row += dir) {
      final target = _at(row, col);
      if (target != null) return _focus(target, cursorCol: col);
    }
  }

  KeyEventResult _onKeyKey(_Placed p, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isSelectKey) {
      if (event is KeyDownEvent) {
        setState(() => _pressedId = p.spec.id);
        _activate(p);
      } else if (event is KeyRepeatEvent) {
        if (p.spec.kind == _KeyKind.backspace) _activate(p);
      } else {
        setState(() => _pressedId = null);
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveHorizontal(p, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveHorizontal(p, 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveVertical(p, -1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveVertical(p, 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Hardware keyboard and `adb shell input text`: printable characters and
  /// Backspace/Delete while focus is inside the keyboard.
  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    if (key.isSelectKey || key.isBackKey) return KeyEventResult.ignored;
    final character = event.character;
    if (character == null || character.isEmpty) return KeyEventResult.ignored;
    if (character.runes.any((rune) => rune < 0x20 || rune == 0x7F)) return KeyEventResult.ignored;
    widget.onInput(character.toLowerCase());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final size = TvTokens.size.keyboard;
    final rows = <Widget>[];
    for (var r = 0; r < _rowCount; r++) {
      final cells = <Widget>[];
      var col = 0;
      while (col < _columns) {
        if (col > 0) cells.add(SizedBox(width: px(size.gap)));
        final p = _at(r, col);
        if (p == null) {
          cells.add(SizedBox(width: px(size.key), height: px(size.key)));
          col++;
          continue;
        }
        final width = size.key * p.span + size.gap * (p.span - 1);
        cells.add(SizedBox(width: px(width), height: px(size.key), child: _buildKey(p)));
        col += p.span;
      }
      if (r > 0) rows.add(SizedBox(height: px(size.gap)));
      rows.add(Row(mainAxisSize: MainAxisSize.min, children: cells));
    }
    return Focus(
      focusNode: _root,
      canRequestFocus: false,
      onKeyEvent: _onRootKey,
      child: FocusTraversalGroup(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      ),
    );
  }

  Widget _buildKey(_Placed p) {
    final id = p.spec.id;
    final focused = _focusedId == id;
    final state = TvFocusState(focused: focused, pressed: focused && _pressedId == id, disabled: false);
    return Focus(
      key: ValueKey('tv-search-key-$id'),
      focusNode: _node(id),
      onFocusChange: (value) => setState(() {
        if (value) {
          _focusedId = id;
        } else if (_focusedId == id) {
          _focusedId = null;
          if (_pressedId == id) _pressedId = null;
        }
      }),
      onKeyEvent: (_, event) => _onKeyKey(p, event),
      child: Semantics(
        button: true,
        label: _semanticLabel(p.spec),
        selected: p.spec.kind == _KeyKind.layout && p.spec.layout == widget.layout,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            _focus(p);
            _activate(p);
          },
          child: TvFocusVisual(
            state: state,
            kind: TvFocusKind.fill,
            focusedScale: TvTokens.focus.buttonScale,
            alignment: Alignment.center,
            radius: TvTokens.radius.iconButton.toDouble(),
            builder: (context, state) => _KeyFace(spec: p.spec, state: state, selected: p.spec.layout == widget.layout),
          ),
        ),
      ),
    );
  }

  String _semanticLabel(_KeySpec spec) => switch (spec.kind) {
    _KeyKind.char => spec.char!,
    _KeyKind.space => TvSearchKeyboardStrings.space,
    _KeyKind.backspace => TvSearchKeyboardStrings.backspace,
    _KeyKind.clear => TvSearchKeyboardStrings.clear,
    _KeyKind.toDigits => TvSearchKeyboardStrings.toDigits,
    _KeyKind.layout => spec.layout!.label,
  };
}

class _KeyFace extends StatelessWidget {
  const _KeyFace({required this.spec, required this.state, required this.selected});

  final _KeySpec spec;
  final TvFocusState state;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final color = state.focused ? TvTokens.color.text.onFocus : TvTokens.color.text.primary;
    final isLetter = spec.kind == _KeyKind.char;
    final style = (isLetter ? theme.title : theme.label).copyWith(color: color);
    final Widget content = switch (spec.kind) {
      _KeyKind.char => Text(spec.char!.toUpperCase(), style: style),
      _KeyKind.space => Icon(Icons.space_bar, size: px(TvTokens.size.iconButton.iconSize), color: color),
      _KeyKind.backspace => Icon(Icons.backspace, size: px(TvTokens.size.iconButton.iconSize), color: color),
      _KeyKind.clear => Text(TvSearchKeyboardStrings.clear, style: style),
      _KeyKind.toDigits => Text(TvSearchKeyboardStrings.toDigits, style: style),
      _KeyKind.layout => Text(spec.layout!.label, style: style),
    };
    final radius = BorderRadius.circular(px(TvTokens.radius.iconButton));
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(color: state.focused ? null : TvTokens.color.surface.level2, borderRadius: radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: content),
            if (spec.kind == _KeyKind.layout && selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: px(TvTokens.size.tab.underline),
                child: ColoredBox(
                  key: const ValueKey('tv-search-layout-selected'),
                  color: TvTokens.color.accent.normal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
