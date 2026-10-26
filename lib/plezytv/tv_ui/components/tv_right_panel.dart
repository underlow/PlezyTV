import 'package:flutter/material.dart';

import '../../../focus/key_event_utils.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// A page of settings rows. Use stable keys for rows whose values can change.
/// [changes] rebuilds the open page without replacing its focus or scroll state.
class TvRightPanelPage {
  const TvRightPanelPage({
    required this.title,
    this.itemsBuilder,
    this.bodyBuilder,
    this.changes,
    this.singleLineTitle = false,
  }) : assert((itemsBuilder == null) != (bodyBuilder == null));

  final String title;

  /// Opt in for titles that must stay on one line; existing pages keep wrapping.
  final bool singleLineTitle;
  final List<Widget> Function(BuildContext context)? itemsBuilder;

  /// A bounded body for pages that own their lazy scrolling viewport.
  final WidgetBuilder? bodyBuilder;
  final Listenable? changes;
}

/// Modal TV settings surface, independent of any library or server.
class TvRightPanel extends StatefulWidget {
  const TvRightPanel({super.key, required this.root});

  final TvRightPanelPage root;

  /// The future completes after closing and restoring the invoking button.
  static Future<void> show({
    required BuildContext context,
    required FocusNode anchor,
    required TvRightPanelPage root,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => TvTheme(child: TvRightPanel(root: root)),
    );
    if (anchor.context != null && anchor.canRequestFocus) anchor.requestFocus();
  }

  static TvRightPanelState of(BuildContext context) => context.findAncestorStateOfType<TvRightPanelState>()!;

  @override
  State<TvRightPanel> createState() => TvRightPanelState();
}

class TvRightPanelState extends State<TvRightPanel> {
  final _pages = <TvRightPanelPage>[];
  final _scopes = <FocusScopeNode>[];

  @override
  void initState() {
    super.initState();
    _add(widget.root);
  }

  void _add(TvRightPanelPage page) {
    _pages.add(page);
    final scope = FocusScopeNode(
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _scopes.add(scope);
    _focus(scope);
  }

  void _focus(FocusScopeNode scope) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scopes.last != scope) return;
      scope.requestFocus();
      if (scope.focusedChild == null) scope.nextFocus();
    });
  }

  void push(TvRightPanelPage page) => setState(() => _add(page));

  void back() {
    if (_pages.length == 1) {
      close();
      return;
    }
    final removed = _scopes.last;
    setState(() {
      _pages.removeLast();
      _scopes.removeLast();
    });
    // Detach the removed page before disposing its focus scope.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    _focus(_scopes.last);
  }

  void close() => Navigator.of(context).pop();

  @override
  void dispose() {
    for (final scope in _scopes) {
      scope.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return PopScope(
      canPop: _pages.length == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Focus(
        onKeyEvent: (node, event) => handleBackKeyAction(event, back),
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: TvTokens.size.rightPanel.background,
            child: SizedBox(
              width: px(TvTokens.size.rightPanel.w),
              height: double.infinity,
              child: IndexedStack(
                index: _pages.length - 1,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    FocusScope(
                      key: ObjectKey(_scopes[i]),
                      node: _scopes[i],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(px(48), px(60), px(48), px(24)),
                            child: Text(
                              '${i > 0 ? '‹ ' : ''}${_pages[i].title}',
                              style: theme.title,
                              maxLines: _pages[i].singleLineTitle ? 1 : null,
                              overflow: _pages[i].singleLineTitle ? TextOverflow.ellipsis : null,
                            ),
                          ),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: _pages[i].changes ?? const AlwaysStoppedAnimation(0),
                              builder: (context, _) =>
                                  (_pages[i].bodyBuilder == null
                                      ? null
                                      : Padding(
                                          padding: EdgeInsets.symmetric(horizontal: px(48), vertical: px(8)),
                                          child: _pages[i].bodyBuilder!(context),
                                        )) ??
                                  SingleChildScrollView(
                                    padding: EdgeInsets.symmetric(horizontal: px(48), vertical: px(8)),
                                    child: Column(children: _pages[i].itemsBuilder!(context)),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
