import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.parts);
  final List<int> parts;
  static ReleaseVersion? parse(String value) {
    if (!RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$').hasMatch(value)) return null;
    return ReleaseVersion(value.split('.').map(int.parse).toList());
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return 0;
  }
}

class UpdateRelease {
  UpdateRelease(this.version, this.url, this.size);
  final String version;
  final Uri url;
  final int size;
}

class UpdateService {
  UpdateService({
    required this.version,
    required this.preferences,
    required this.abi,
    required this.cache,
    required this.log,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  }) : clientFactory = clientFactory ?? http.Client.new,
       now = now ?? DateTime.now;
  static const lastCheckKey = 'plezytv.update.lastAutomaticRequest';
  static const skippedKey = 'plezytv.update.skippedVersion';
  final String version;
  final SharedPreferences preferences;
  final Future<String> Function() abi;
  final Directory cache;
  final void Function(String) log;
  final http.Client Function() clientFactory;
  final DateTime Function() now;
  bool get enabled => ReleaseVersion.parse(version) != null;
  bool _checking = false;
  http.Client? _downloadClient;
  bool _cancelled = false;
  Completer<void>? _cancelSignal;
  File? _complete;
  String? _completeVersion;

  Future<UpdateRelease?> check({required bool automatic}) async {
    if (!enabled || _checking) return null;
    final timestamp = now().millisecondsSinceEpoch;
    final previous = preferences.getInt(lastCheckKey);
    if (automatic && previous != null && timestamp - previous < const Duration(hours: 6).inMilliseconds) return null;
    _checking = true;
    final client = clientFactory();
    try {
      final installedAbi = await abi();
      if (automatic) await preferences.setInt(lastCheckKey, now().millisecondsSinceEpoch);
      final response = await client
          .get(
            Uri.https('api.github.com', '/repos/underlow/PlezyTV/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('GitHub HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String? ?? '';
      final latest = tag.startsWith('v') ? ReleaseVersion.parse(tag.substring(1)) : null;
      if (latest == null) {
        log('PlezyTV update: invalid release tag $tag');
        return null;
      }
      if (latest.compareTo(ReleaseVersion.parse(version)!) <= 0) return null;
      if (automatic && preferences.getString(skippedKey) == tag.substring(1)) return null;
      final name = 'plezytv-$tag-$installedAbi.apk';
      final assets = (data['assets'] as List).cast<Map<String, dynamic>>();
      final matching = assets.where((asset) => asset['name'] == name).firstOrNull;
      if (matching == null) throw const HttpException('No compatible APK');
      final url = Uri.parse(matching['browser_download_url'] as String);
      if (url.scheme != 'https' ||
          url.host != 'github.com' ||
          !url.path.startsWith('/underlow/PlezyTV/releases/download/')) {
        throw const HttpException('Invalid APK URL');
      }
      return UpdateRelease(tag.substring(1), url, matching['size'] as int);
    } catch (error) {
      if (!automatic) rethrow;
      log('PlezyTV update check failed: $error');
      return null;
    } finally {
      client.close();
      _checking = false;
    }
  }

  Future<void> skip(UpdateRelease release) => preferences.setString(skippedKey, release.version);
  Future<void> cleanup() async {
    if (!await cache.exists()) return;
    await for (final file in cache.list()) {
      if (file is File && file.uri.pathSegments.last.startsWith('plezytv-update-')) await file.delete();
    }
    _complete = null;
    _completeVersion = null;
  }

  void cancel() {
    _cancelled = true;
    if (_cancelSignal?.isCompleted == false) _cancelSignal!.complete();
    _downloadClient?.close();
  }

  Future<File> download(UpdateRelease release, void Function(double?) progress) async {
    _cancelled = false;
    _cancelSignal = Completer<void>();
    if (_completeVersion == release.version && _complete != null && await _complete!.exists()) return _complete!;
    await cleanup();
    await cache.create(recursive: true);
    if (_cancelled) throw const HttpException('Download cancelled');
    final partial = File('${cache.path}/plezytv-update-${release.version}.part');
    final complete = File('${cache.path}/plezytv-update-${release.version}.apk');
    final client = clientFactory();
    _downloadClient = client;
    RandomAccessFile? output;
    StreamIterator<List<int>>? chunks;
    Future<T> cancellable<T>(Future<T> future) =>
        Future.any([future, _cancelSignal!.future.then<T>((_) => throw const HttpException('Download cancelled'))]);
    try {
      final response = await cancellable(
        client.send(http.Request('GET', release.url)).timeout(const Duration(seconds: 30)),
      );
      if (response.statusCode != 200) throw HttpException('Download HTTP ${response.statusCode}');
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      chunks = StreamIterator(response.stream.timeout(const Duration(seconds: 30)));
      while (await cancellable(chunks.moveNext())) {
        final chunk = chunks.current;
        if (_cancelled) throw const HttpException('Download cancelled');
        await output.writeFrom(chunk);
        received += chunk.length;
        progress(release.size > 0 ? (received / release.size).clamp(0, 1) : null);
      }
      await output.flush();
      await output.close();
      output = null;
      if (_cancelled) throw const HttpException('Download cancelled');
      if (received == 0 || (release.size > 0 && received != release.size)) {
        throw const HttpException('Incomplete APK download');
      }
      _complete = await partial.rename(complete.path);
      _completeVersion = release.version;
      return _complete!;
    } finally {
      client.close();
      _downloadClient = null;
      _cancelSignal = null;
      try {
        await chunks?.cancel();
        await output?.close();
      } finally {
        if (await partial.exists()) await partial.delete();
      }
    }
  }
}
