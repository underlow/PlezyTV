import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/device_performance.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// A single action row whose icon captions paint outside its layout bounds.
class TvActionRow extends StatelessWidget {
  const TvActionRow({super.key, required this.buttons, this.rowKey});
  final List<Widget> buttons;
  final Key? rowKey;
  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        key: rowKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: px(TvTokens.space.actionsGap)),
            Focus(
              canRequestFocus: false,
              onFocusChange: (inside) {
                if (!inside) return;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  final anchor = FocusManager.instance.primaryFocus?.context;
                  if (anchor != null) {
                    unawaited(
                      Scrollable.ensureVisible(
                        anchor,
                        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                        duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : 150),
                      ),
                    );
                  }
                });
              },
              child: buttons[i],
            ),
          ],
        ],
      ),
    );
  }
}
