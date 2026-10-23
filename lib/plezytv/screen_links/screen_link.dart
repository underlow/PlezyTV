enum ScreenTarget { home, libraries, library, item, search, downloads, settings, update }

class ScreenLink {
  final String source;
  final ScreenTarget target;
  final String? id;
  final String? server;
  final String? query;

  const ScreenLink(this.source, this.target, {this.id, this.server, this.query});

  static bool claims(String source) {
    final uri = Uri.tryParse(source);
    return uri?.scheme == 'plezytv' && uri?.host == 'screen';
  }

  /// Throws FormatException with a user-facing reason; never performs IO.
  static ScreenLink parse(String source) {
    final uri = Uri.tryParse(source);
    if (!claims(source) || uri == null) throw const FormatException('invalid screen URI');
    if (uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment || uri.pathSegments.length != 1) {
      throw const FormatException('invalid screen path');
    }
    final name = uri.pathSegments.single;
    final target = ScreenTarget.values.where((value) => value.name == name).firstOrNull;
    if (target == null) throw FormatException('unknown target $name');
    for (final entry in uri.queryParametersAll.entries) {
      if (!const ['id', 'server', 'q'].contains(entry.key) || entry.value.length != 1) {
        throw FormatException('invalid parameter ${entry.key}');
      }
    }
    final id = uri.queryParameters['id'];
    final server = uri.queryParameters['server'];
    if ((target == ScreenTarget.library || target == ScreenTarget.item) && (id == null || id.trim().isEmpty)) {
      throw const FormatException('missing required parameter id');
    }
    if (server != null && server.trim().isEmpty) throw const FormatException('empty server');
    return ScreenLink(source, target, id: id, server: server, query: uri.queryParameters['q']);
  }
}
