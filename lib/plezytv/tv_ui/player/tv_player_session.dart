import 'package:flutter/widgets.dart';

import '../../../mpv/mpv.dart';

/// TV player state that outlives the panel: Plezy unmounts the controls while
/// they are hidden, so anything the next showing needs lives here, one
/// instance per [Player].
///
/// Owned fields (S9 design §4): focus memory (an element id, never a focus
/// node) and when the panel was hidden, the "focus play on next show" flag,
/// whether the right panel is open, and the icons-row focus node the skip
/// button moves down to. Focus memory (id and hide time) resets when the
/// playing item changes; the play flag does not, since H7 may set it for the
/// new item before the panel next binds.
class TvPlayerSession {
  TvPlayerSession._();

  static final Expando<TvPlayerSession> _sessions = Expando<TvPlayerSession>('TvPlayerSession');

  /// The session for [player], created on first use.
  static TvPlayerSession of(Player player) => _sessions[player] ??= TvPlayerSession._();

  String? _itemKey;

  /// Key of the item the session currently describes.
  String? get itemKey => _itemKey;

  /// Id of the panel element that had focus when the panel last hid.
  String? lastFocusedId;

  /// When the panel last hid; focus memory is honoured only shortly after.
  DateTime? hiddenAt;

  /// The next showing focuses play (pause from the remote with the panel hidden).
  bool focusPlayOnNextShow = false;

  /// Whether the right panel is open; the skip button hides while it is.
  final ValueNotifier<bool> sidePanelOpen = ValueNotifier<bool>(false);

  /// The icons row, registered by the panel while mounted.
  FocusNode? iconsFocusNode;

  /// Records the item now playing; a different item drops focus memory.
  void bindItem(String itemKey) {
    if (_itemKey == itemKey) return;
    final hadItem = _itemKey != null;
    _itemKey = itemKey;
    if (hadItem) resetFocusMemory();
  }

  /// Remembers [elementId] as focused at [at] (when the panel hides).
  void rememberFocus(String? elementId, DateTime at) {
    lastFocusedId = elementId;
    hiddenAt = at;
  }

  void resetFocusMemory() {
    lastFocusedId = null;
    hiddenAt = null;
  }
}
