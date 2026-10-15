import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import 'update_contract.dart';

/// Anonymous, bounded GitHub reads. Package URLs are derived, never supplied by
/// release notes or arbitrary metadata. APK signatures supply publisher trust.
class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;
  final Map<String, (String, dynamic)> _cache = {};
  DateTime? _notBefore;
  void close() => _client.close(force: true);
  Future<dynamic> _json(Uri uri) async {
    try {
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set('User-Agent', 'IHTD-updater');
      request.headers.set('Accept', 'application/vnd.github+json');
      final cached = _cache['$uri'];
      if (cached != null) request.headers.set('If-None-Match', cached.$1);
      var response = await request.close().timeout(const Duration(seconds: 20));
      // GitHub release downloads redirect to a CDN. No auth header is ever sent.
      for (var i = 0; response.isRedirect && i < 5; i++) {
        final next = uri.resolve(response.headers.value('location') ?? '');
        if (next.scheme != 'https' ||
            next.userInfo.isNotEmpty ||
            !const {
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(next.host)) {
          throw const UpdateFailure('invalid_redirect');
        }
        await response.drain<void>();
        final redirected = await _client
            .getUrl(next)
            .timeout(const Duration(seconds: 20));
        redirected.followRedirects = false;
        response = await redirected.close().timeout(
          const Duration(seconds: 20),
        );
      }
      if (response.statusCode == 304 && cached != null) {
        await response.drain<void>();
        return cached.$2;
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        final seconds = int.tryParse(
          response.headers.value('retry-after') ?? '',
        );
        final reset = int.tryParse(
          response.headers.value('x-ratelimit-reset') ?? '',
        );
        _notBefore = DateTime.now().add(
          Duration(
            seconds:
                (seconds ??
                        (reset == null
                            ? 3600
                            : reset -
                                  DateTime.now().millisecondsSinceEpoch ~/
                                      1000))
                    .clamp(60, 86400),
          ),
        );
        await response.drain<void>();
        throw const UpdateFailure('rate_limited');
      }
      if (response.statusCode == 404) {
        await response.drain<void>();
        throw const UpdateFailure('feed_unavailable');
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const UpdateFailure('network');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 1048576) {
          throw const UpdateFailure('invalid_metadata');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      final etag = response.headers.value('etag');
      if (etag != null && _cache.length < 10) _cache['$uri'] = (etag, data);
      return data;
    } on UpdateFailure {
      rethrow;
    } on FormatException {
      throw const UpdateFailure('invalid_metadata');
    } on SocketException {
      throw const UpdateFailure('offline');
    } on TimeoutException {
      throw const UpdateFailure('offline');
    } on HttpException {
      throw const UpdateFailure('network');
    }
  }

  @override
  Future<UpdateCandidate?> latest(InstalledApp app) async {
    if (_notBefore != null && DateTime.now().isBefore(_notBefore!)) {
      throw const UpdateFailure('rate_limited');
    }
    final releases = <Map<String, dynamic>>[];
    for (var page = 1; page <= 3; page++) {
      final data = await _json(
        Uri.https('api.github.com', '/repos/$updateRepository/releases', {
          'per_page': '30',
          'page': '$page',
        }),
      );
      if (data is! List) throw const UpdateFailure('invalid_metadata');
      for (final raw in data) {
        if (raw is! Map<String, dynamic> ||
            raw['draft'] != false ||
            raw['prerelease'] != false ||
            raw['published_at'] == null) {
          continue;
        }
        final tag = raw['tag_name'];
        if (tag is String && RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
          releases.add(raw);
        }
      }
      if (data.length < 30) break;
    }
    releases.sort(
      (a, b) =>
          Version.parse((b['tag_name'] as String).substring(1))
              .compareTo(Version.parse((a['tag_name'] as String).substring(1))),
    );
    for (final release in releases) {
      final tag = release['tag_name'] as String;
      if (Version.parse(tag.substring(1)) <= app.version) return null;
      final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
      final metadata = assets.where((a) => a['name'] == 'update.json').toList();
      if (metadata.isEmpty) {
        continue; // Legacy releases predate updater contract.
      }
      if (metadata.length != 1) throw const UpdateFailure('invalid_metadata');
      final manifest = await _json(
        Uri.https(
          'github.com',
          '/$updateRepository/releases/download/$tag/update.json',
        ),
      );
      final candidate = selectUpdate(
        manifest,
        assets,
        app,
        tag: tag,
        notes: '${release['body'] ?? ''}',
      );
      if (candidate != null) return candidate;
    }
    return null;
  }
}

UpdateCandidate? selectUpdate(
  dynamic raw,
  List<Map<String, dynamic>> assets,
  InstalledApp app, {
  required String tag,
  required String notes,
}) {
  if (raw is! Map ||
      raw['schema'] != 1 ||
      raw['tag'] != tag ||
      raw['version'] != tag.substring(1) ||
      !RegExp(r'^[a-f0-9]{40}$').hasMatch('${raw['commit']}') ||
      raw['packages'] is! List) {
    throw const UpdateFailure('invalid_metadata');
  }
  final packages = (raw['packages'] as List).cast<Map<String, dynamic>>();
  // Complete release means all supported installation packages exist exactly once.
  for (final platform in ['android', 'windows', 'fedora']) {
    final entries = packages.where((p) => p['platform'] == platform).toList();
    if (entries.length != 1) throw const UpdateFailure('invalid_metadata');
    final p = entries.single;
    final candidate = UpdateCandidate.fromJson({
      ...p,
      'version': raw['version'],
      'build': raw['build'],
      'tag': tag,
      'notes': notes,
    });
    final found = assets.where((a) => a['name'] == candidate.name).toList();
    if (found.length != 1 ||
        found.single['size'] != candidate.size ||
        found.single['state'] != 'uploaded') {
      throw const UpdateFailure('incomplete_release');
    }
  }
  final selected = packages
      .where((p) => p['platform'] == app.platform && p['arch'] == app.arch)
      .toList();
  if (selected.length != 1) throw const UpdateFailure('unsupported_device');
  final p = selected.single;
  if (app.platform == 'android' &&
      (app.api < (p['minApi'] as int) ||
          p['packageId'] != 'dev.ihtd.app' ||
          p['certificate'] != androidReleaseCertificate)) {
    throw const UpdateFailure('unsupported_device');
  }
  if (app.platform == 'fedora' && p['distribution'] != 'fedora44') {
    throw const UpdateFailure('unsupported_device');
  }
  final candidate = UpdateCandidate.fromJson({
    ...p,
    'version': raw['version'],
    'build': raw['build'],
    'tag': tag,
    'notes': notes,
  });
  return candidate.newerThan(app) ? candidate : null;
}
