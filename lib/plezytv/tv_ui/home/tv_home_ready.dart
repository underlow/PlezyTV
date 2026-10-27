import 'package:flutter/widgets.dart';

/// Post-frame probe: data alone or an image placeholder is not readiness.
/// Row bounds include headers: a partially visible row still needs a built,
/// painted first poster even when that poster starts below the viewport.
int? tvHomeReadyRows(Rect viewport, Iterable<BuildContext?> posters, {List<Rect>? rowBounds}) {
  var visible = 0;
  var ready = true;
  var index = 0;
  for (final context in posters) {
    final bounds = rowBounds?[index++];
    if (bounds != null && !bounds.overlaps(viewport)) continue;
    final render = context?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      if (bounds != null) {
        visible++;
        ready = false;
      }
      continue;
    }
    final rect = render.localToGlobal(Offset.zero) & render.size;
    if (bounds == null && !rect.overlaps(viewport)) continue;
    visible++;
    var painted = false;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is RawImage && widget.image != null) painted = true;
      element.visitChildren(visit);
    }

    visit(context! as Element);
    if (!painted) ready = false;
  }
  return visible > 0 && ready ? visible : null;
}
