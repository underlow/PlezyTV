import 'package:flutter/widgets.dart';

/// Post-frame probe: data alone or an image placeholder is not readiness.
/// The caller supplies the first poster subtree of each row and its viewport.
int? tvHomeReadyRows(Rect viewport, Iterable<BuildContext?> posters) {
  var visible = 0;
  var ready = true;
  for (final context in posters) {
    final render = context?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final rect = render.localToGlobal(Offset.zero) & render.size;
    if (!rect.overlaps(viewport)) continue;
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
