import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/library_filter_selection.dart';
import '../../../media/library_query.dart';
import '../../../media/media_filter.dart';
import '../../../screens/libraries/filters/filter_summary.dart';
import '../../../services/plex_client.dart';
import '../../../screens/libraries/library_browse_grouping.dart';
import '../components/tv_right_panel.dart';
import '../components/tv_settings_item.dart';
import '../tv_strings.dart';
import 'tv_library_controller.dart';
import 'tv_library_query.dart';

Widget _row(
  String id,
  String title,
  VoidCallback action, {
  bool? selected,
  String value = '',
  TvSettingsItemKind? kind,
}) => TvSettingsItem(
  key: ValueKey(id),
  icon: Icons.tune,
  title: title,
  description: '',
  value: value,
  kind: kind ?? (selected == null ? TvSettingsItemKind.action : TvSettingsItemKind.singleChoice),
  selected: selected ?? false,
  onSelect: action,
);

Future<void> showTvLibrarySort(BuildContext context, FocusNode anchor, TvLibraryController c) => TvRightPanel.show(
  context: context,
  anchor: anchor,
  root: TvRightPanelPage(
    title: t.libraries.sortBy,
    changes: c,
    itemsBuilder: (context) => [
      _row(
        'grouping',
        t.libraries.groupings.title,
        () => TvRightPanel.of(context).push(
          TvRightPanelPage(
            title: t.libraries.groupings.title,
            changes: c,
            itemsBuilder: (_) => [
              for (final group in c.groupingOptions)
                _row(
                  'group:$group',
                  tvGroupingLabel(group),
                  () => unawaited(c.select(grouping: group)),
                  selected: c.grouping == group,
                ),
            ],
          ),
        ),
        value: tvGroupingLabel(c.grouping),
        kind: TvSettingsItemKind.page,
      ),
      for (final sort in c.sorts)
        _row(
          'sort:${sort.key}',
          sort.title,
          () => unawaited(c.select(sort: sort)),
          selected: c.selectedSort?.key == sort.key,
        ),
      _row(
        'direction',
        TvStrings.descending,
        () => unawaited(c.select(descending: !c.preferences.descending)),
        selected: c.preferences.descending,
        kind: TvSettingsItemKind.toggle,
      ),
      _row(
        'reset',
        t.common.reset,
        () => unawaited(
          c.select(
            grouping: defaultLibraryBrowseGrouping(c.library, canGroupByFolders: c.canGroupByFolders),
            clearSort: true,
          ),
        ),
      ),
    ],
  ),
);

Future<void> showTvLibraryFilters(BuildContext context, FocusNode anchor, TvLibraryController c) => TvRightPanel.show(
  context: context,
  anchor: anchor,
  root: TvRightPanelPage(
    title: t.libraries.filters,
    changes: c,
    itemsBuilder: (context) => [
      for (final filter in c.filterResult.filters)
        _row(
          filter.filter,
          filter.title,
          () => TvRightPanel.of(context).push(
            TvRightPanelPage(
              title: filter.title,
              changes: c,
              itemsBuilder: (_) => [TvLibraryFilterEditor(key: ValueKey(filter.filter), controller: c, filter: filter)],
            ),
          ),
          kind: TvSettingsItemKind.page,
          value:
              filterFieldSummary(
                filter: filter,
                clauses: c.preferences.filters,
                serverId: c.library.serverId ?? '',
                libraryKey: c.library.id,
              ) ??
              '',
        ),
      _row('clear', t.libraries.clearAll, () => unawaited(c.resetFilters())),
    ],
  ),
);

/// Native platform input is shared with Plezy, with the TV overlay explicitly disabled.
class TvLibraryFilterEditor extends StatefulWidget {
  const TvLibraryFilterEditor({super.key, required this.controller, required this.filter});
  final TvLibraryController controller;
  final MediaFilter filter;
  @override
  State<TvLibraryFilterEditor> createState() => _TvLibraryFilterEditorState();
}

class _TvLibraryFilterEditorState extends State<TvLibraryFilterEditor> {
  final _inputNodes = <TextEditingController, FocusNode>{};
  final _inputHandles = <TextEditingController, TvTextInputController>{};
  List<MediaFilterValue>? values;
  Object? error;
  late LibraryFilterOperator mode;
  late final TextEditingController text, lower, upper;
  TvLibraryController get c => widget.controller;
  MediaFilter get f => widget.filter;
  List<LibraryFilter> get clauses => c.preferences.filters.clausesFor(f.filter);
  @override
  void initState() {
    super.initState();
    mode = clauses.firstOrNull?.op ?? f.operators.first;
    text = TextEditingController(text: clauses.firstOrNull?.values.firstOrNull ?? '');
    String bound(LibraryFilterOperator op) {
      final raw = clauses.where((x) => x.op == op).firstOrNull?.values.firstOrNull;
      return raw == null ? '' : '${(int.tryParse(raw) ?? 0) ~/ f.unit.scale}';
    }

    lower = TextEditingController(text: bound(LibraryFilterOperator.atLeast));
    upper = TextEditingController(text: bound(LibraryFilterOperator.atMost));
    if (f.editorKind == FilterEditorKind.valueList) unawaited(load());
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final result =
          c.filterResult.cachedValues[f.filter] ??
          (c.client is PlexClient ? await (c.client as PlexClient).getFilterValues(f.key) : <MediaFilterValue>[]);
      if (mounted) {
        for (final value in result) {
          FilterValueNames.remember(
            serverId: c.library.serverId ?? '',
            libraryKey: c.library.id,
            field: f.filter,
            value: libraryFilterValueId(value.key, f.filter),
            title: value.title,
          );
        }
        setState(() => values = result);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  void apply(List<LibraryFilter> next) => unawaited(c.select(filters: c.preferences.filters.withField(f.filter, next)));
  LibraryFilter clause(String value, LibraryFilterOperator op) =>
      LibraryFilter(field: f.filter, op: op, values: [value]);
  void emitText() => apply(text.text.trim().isEmpty ? [] : [clause(text.text.trim(), mode)]);
  Widget field(TextEditingController input, String label, VoidCallback changed, {bool number = false}) =>
      FocusableTextField(
        controller: input,
        focusNode: _inputNodes.putIfAbsent(input, () => FocusNode(debugLabel: 'Filter input $label')),
        tvTextInputController: _inputHandles.putIfAbsent(input, TvTextInputController.new),
        onEditingComplete: () {
          _inputHandles[input]!.closeTextInput();
          unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
          _inputNodes[input]!.requestFocus();
        },
        tvTextInputPresentation: TvTextInputPresentation.platform,
        decoration: InputDecoration(labelText: label, suffixText: number ? f.unit.suffix : null),
        keyboardType: number ? TextInputType.number : TextInputType.text,
        onChanged: (_) => changed(),
      );
  void emitBounds() => apply([
    for (final pair in [(lower, LibraryFilterOperator.atLeast), (upper, LibraryFilterOperator.atMost)])
      if (int.tryParse(pair.$1.text.trim()) case final value?) clause('${value * f.unit.scale}', pair.$2),
  ]);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _row('clear', t.libraries.all, () {
        text.clear();
        lower.clear();
        upper.clear();
        apply([]);
      }, selected: clauses.isEmpty),
      if (f.editorKind == FilterEditorKind.toggle)
        for (final value in ['1', '0'])
          _row(
            value,
            value == '1' ? t.libraries.advancedFilters.yes : t.libraries.advancedFilters.no,
            () => apply([clause('1', value == '1' ? LibraryFilterOperator.is_ : LibraryFilterOperator.isNot)]),
            selected: clauses.isNotEmpty && clauses.first.op.isNegated == (value == '0'),
          ),
      if (f.editorKind == FilterEditorKind.valueList) ...[
        if (error != null)
          _row('retry', TvStrings.retry, () => unawaited(load()))
        else if (values == null)
          const LinearProgressIndicator()
        else ...[
          if (f.supportsExclusion)
            _row(
              'exclude',
              TvStrings.exclude,
              () {
                setState(() => mode = mode.isNegated ? LibraryFilterOperator.is_ : LibraryFilterOperator.isNot);
                apply([for (final x in clauses) x.copyWith(op: mode)]);
              },
              selected: mode.isNegated,
              kind: TvSettingsItemKind.toggle,
            ),
          for (final value in values!)
            _row(
              value.key,
              value.title,
              () {
                final id = libraryFilterValueId(value.key, f.filter);
                final selected = clauses.expand((x) => x.values).toSet();
                if (!selected.remove(id)) selected.add(id);
                apply(selected.isEmpty ? [] : [LibraryFilter(field: f.filter, op: mode, values: selected.toList())]);
              },
              selected: clauses.any((x) => x.values.contains(libraryFilterValueId(value.key, f.filter))),
              kind: TvSettingsItemKind.multipleChoice,
            ),
        ],
      ],
      if (f.editorKind == FilterEditorKind.number) ...[
        field(lower, t.libraries.advancedFilters.from, emitBounds, number: true),
        field(upper, t.libraries.advancedFilters.to, emitBounds, number: true),
      ],
      if (f.editorKind == FilterEditorKind.date)
        for (final op in [LibraryFilterOperator.atLeast, LibraryFilterOperator.atMost])
          if (f.operators.contains(op))
            for (final window in relativeDateWindows)
              _row(
                '$op:$window',
                relativeDateLabel(window, older: op == LibraryFilterOperator.atMost),
                () => apply([clause(window, op)]),
                selected: clauses.any((x) => x.op == op && x.values.contains(window)),
              ),
      if (f.editorKind == FilterEditorKind.text) ...[
        for (final op in f.operators)
          _row(op.id, _operatorLabel(op), () {
            setState(() => mode = op);
            emitText();
          }, selected: mode == op),
        field(text, f.title, emitText),
      ],
    ],
  );
  String _operatorLabel(LibraryFilterOperator op) => switch (op) {
    LibraryFilterOperator.is_ => t.libraries.advancedFilters.matchContains,
    LibraryFilterOperator.isNot => t.libraries.advancedFilters.matchNotContains,
    LibraryFilterOperator.matches => t.libraries.advancedFilters.matchIs,
    LibraryFilterOperator.notMatches => t.libraries.advancedFilters.matchIsNot,
    LibraryFilterOperator.beginsWith => t.libraries.advancedFilters.matchBeginsWith,
    LibraryFilterOperator.endsWith => t.libraries.advancedFilters.matchEndsWith,
    _ => op.id,
  };
  @override
  void dispose() {
    for (final node in _inputNodes.values) {
      node.dispose();
    }
    text.dispose();
    lower.dispose();
    upper.dispose();
    super.dispose();
  }
}
