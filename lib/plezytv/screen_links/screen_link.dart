enum ScreenTarget {
  home,
  libraries,
  library,
  libraryFilter,
  item,
  search,
  downloads,
  settings,
  update,
  settingsExport,
  settingsImport,
}

class ScreenLink {
  final String source;
  final ScreenTarget target;
  final String? id;
  final String? server;
  final String? query;
  final String? field, value;

  const ScreenLink(this.source, this.target, {this.id, this.server, this.query, this.field, this.value});

  static bool claims(String source) {
    final uri = Uri.tryParse(source);
    return uri?.scheme == 'plezytv' && (uri?.host == 'screen' || uri?.host == 'settings');
  }

  /// Throws FormatException with a user-facing reason; never performs IO.
  static ScreenLink parse(String source) {
    final uri = Uri.tryParse(source);
    if (!claims(source) || uri == null) throw const FormatException('invalid screen URI');
    if (uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment || uri.pathSegments.length != 1) {
      throw const FormatException('invalid screen path');
    }
    final name = uri.pathSegments.single;
    if (uri.host == 'settings') {
      if (uri.hasQuery) throw const FormatException('settings links do not accept parameters');
      final target = switch (name) {
        'export' => ScreenTarget.settingsExport,
        'import' => ScreenTarget.settingsImport,
        _ => throw FormatException('unknown settings action $name'),
      };
      return ScreenLink(source, target);
    }
    final target = name == 'library-filter'
        ? ScreenTarget.libraryFilter
        : ScreenTarget.values
              .where(
                (value) =>
                    value != ScreenTarget.libraryFilter &&
                    value != ScreenTarget.settingsExport &&
                    value != ScreenTarget.settingsImport &&
                    value.name == name,
              )
              .firstOrNull;
    if (target == null) throw FormatException('unknown target $name');
    for (final entry in uri.queryParametersAll.entries) {
      if (!(target == ScreenTarget.libraryFilter
                  ? const ['id', 'server', 'field', 'value']
                  : const ['id', 'server', 'q'])
              .contains(entry.key) ||
          entry.value.length != 1) {
        throw FormatException('invalid parameter ${entry.key}');
      }
    }
    final id = uri.queryParameters['id'];
    final server = uri.queryParameters['server'];
    if ((target == ScreenTarget.library || target == ScreenTarget.item || target == ScreenTarget.libraryFilter) &&
        (id == null || id.trim().isEmpty)) {
      throw const FormatException('missing required parameter id');
    }
    if (id != null && (id.isEmpty || RegExp(r'[^0-9]').hasMatch(id))) {
      throw const FormatException('invalid id');
    }
    if (target == ScreenTarget.libraryFilter) {
      for (final key in ['field', 'value']) {
        if (uri.queryParameters[key]?.trim().isNotEmpty != true) {
          throw FormatException('missing required parameter $key');
        }
      }
    }
    // Plex machine identifiers and UUIDs use ASCII letters, digits and hyphens.
    if (server != null && (server.isEmpty || RegExp(r'[^A-Za-z0-9-]').hasMatch(server))) {
      throw const FormatException('invalid server');
    }
    return ScreenLink(
      source,
      target,
      id: id,
      server: server,
      query: uri.queryParameters['q'],
      field: uri.queryParameters['field'],
      value: uri.queryParameters['value'],
    );
  }
}
