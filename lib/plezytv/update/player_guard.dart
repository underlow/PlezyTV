import 'package:flutter/widgets.dart';
import '../../utils/video_player_navigation.dart' show VideoPlayerRoute;

/// Query the route owner directly, without walking/rebuilding the widget tree.
bool hasActiveUpdatePlayer(NavigatorState? navigator) => VideoPlayerRoute.hasActivePlayer(navigator);
