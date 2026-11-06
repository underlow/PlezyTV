import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../components/tv_button.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import 'tv_library_controller.dart';
import 'tv_library_more.dart';
import 'tv_library_panels.dart';
import 'tv_library_query.dart';

/// Browse controls own stable panel anchors and the horizontal focus path.
class TvLibraryBrowseBar extends StatefulWidget {
  const TvLibraryBrowseBar({
    super.key,
    required this.controller,
    required this.onDown,
    required this.onLeft,
    this.onSort,
    this.onFilters,
    this.onMore,
  });

  final TvLibraryController controller;
  final VoidCallback onDown, onLeft;
  final ValueChanged<FocusNode>? onSort, onFilters, onMore;

  @override
  State<TvLibraryBrowseBar> createState() => TvLibraryBrowseBarState();
}

class TvLibraryBrowseBarState extends State<TvLibraryBrowseBar> {
  final _filters = FocusNode(debugLabel: 'Library filters');
  final _grouping = FocusNode(debugLabel: 'Library grouping');
  final _sort = FocusNode(debugLabel: 'Library sort');
  final _clear = FocusNode(debugLabel: 'Library clear');
  final _more = FocusNode(debugLabel: 'Library more');

  void requestFocus() => _filters.requestFocus();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final count = c.activeFilterCount;
    final quick = c.selectedQuickFilter;
    final filterLabel = count == 0
        ? t.libraries.all
        : count == 1 && quick != null
        ? quick == TvLibraryQuickFilter.unwatched
              ? t.libraries.filterCategories.unwatched
              : c.quickFilters[quick]?.title ?? '${t.libraries.filters} · $count'
        : '${t.libraries.filters} · $count';
    final nodes = [_filters, if (c.groupingOptions.length > 1) _grouping, _sort, if (count > 0) _clear, _more];
    Widget button(String label, FocusNode node, VoidCallback select, {bool disabled = false}) {
      final index = nodes.indexOf(node);
      return TvButton(
        key: ValueKey(node),
        label: label,
        focusNode: node,
        variant: TvButtonVariant.smallSecondary,
        minWidth: 0,
        disabled: disabled,
        onSelect: select,
        // The bar shares the top line with the tabs: nothing lies above it.
        onNavigateUp: () {},
        onNavigateDown: widget.onDown,
        onNavigateLeft: index == 0 ? widget.onLeft : nodes[index - 1].requestFocus,
        onNavigateRight: index == nodes.length - 1 ? () {} : nodes[index + 1].requestFocus,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          button(filterLabel, _filters, () {
            if (widget.onFilters case final callback?) {
              callback(_filters);
            } else {
              unawaited(showTvLibraryFilters(context, _filters, c));
            }
          }, disabled: c.filtersLoading),
          if (c.groupingOptions.length > 1) ...[
            SizedBox(width: px(16)),
            button(
              tvGroupingLabel(c.grouping),
              _grouping,
              () => unawaited(showTvLibraryGrouping(context, _grouping, c)),
            ),
          ],
          SizedBox(width: px(16)),
          Text('by', style: theme.caption),
          SizedBox(width: px(16)),
          button(c.effectiveSort?.title ?? TvStrings.defaultSort, _sort, () {
            if (widget.onSort case final callback?) {
              callback(_sort);
            } else {
              unawaited(showTvLibrarySort(context, _sort, c));
            }
          }),
          SizedBox(width: px(24)),
          Text(c.totalCount == null ? '—' : '${c.totalCount}', style: theme.caption),
          if (count > 0) ...[
            SizedBox(width: px(16)),
            button('Clear', _clear, () {
              _filters.requestFocus();
              unawaited(c.resetFilters());
            }),
          ],
          SizedBox(width: px(16)),
          button('⋮', _more, () {
            if (widget.onMore case final callback?) {
              callback(_more);
            } else {
              unawaited(showTvLibraryMore(context, _more, c.library, c.client));
            }
          }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final node in [_filters, _grouping, _sort, _clear, _more]) {
      node.dispose();
    }
    super.dispose();
  }
}
