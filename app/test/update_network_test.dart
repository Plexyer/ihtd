import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/services/update_catalog.dart';
import 'package:app/services/update_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

class Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.statusCode, this.data, {String? location, String? etag}) {
    if (location != null) headers.set('location', location);
    if (etag != null) headers.set('etag', etag);
  }
  final String data;
  @override
  final int statusCode;
  @override
  final Headers headers = Headers();
  @override
  bool get isRedirect => statusCode == 302;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(data)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  bool followRedirects = true;
  @override
  final Headers headers = Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  final responses = <Response>[];
  final requests = <Request>[];
  final urls = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    urls.add(uri);
    final request = Request(responses.removeAt(0));
    requests.add(request);
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final app = InstalledApp(
    Version.parse('0.2.3'),
    12,
    'android',
    'arm64',
    api: 35,
  );
  test(
    'drafts and prereleases do not create download requests; no credentials',
    () async {
      final client = Client()
        ..responses.add(
          Response(
            200,
            jsonEncode([
              {
                'draft': true,
                'prerelease': false,
                'tag_name': 'v9.0.0',
                'published_at': 'date',
              },
              {
                'draft': false,
                'prerelease': true,
                'tag_name': 'v8.0.0',
                'published_at': 'date',
              },
            ]),
          ),
        );
      expect(await GitHubReleaseSource(client: client).latest(app), isNull);
      expect(client.urls.length, 1);
      expect(client.requests.single.headers.value('Authorization'), isNull);
    },
  );
  test('rate-limit error does not mean up to date', () async {
    final client = Client()..responses.add(Response(429, '{}'));
    await expectLater(
      GitHubReleaseSource(client: client).latest(app),
      throwsA(
        isA<UpdateFailure>().having((e) => e.code, 'code', 'rate_limited'),
      ),
    );
  });
  test('private feed returns clear unavailable state', () async {
    final client = Client()..responses.add(Response(404, '{}'));
    await expectLater(
      GitHubReleaseSource(client: client).latest(app),
      throwsA(
        isA<UpdateFailure>().having((e) => e.code, 'code', 'feed_unavailable'),
      ),
    );
  });
  test('ETag cache revalidation handles 304', () async {
    final client = Client()
      ..responses.addAll([
        Response(200, '[]', etag: 'cache'),
        Response(304, ''),
      ]);
    final source = GitHubReleaseSource(client: client);
    expect(await source.latest(app), isNull);
    expect(await source.latest(app), isNull);
    expect(client.requests.last.headers.value('If-None-Match'), 'cache');
  });
  test('untrusted redirect refused', () async {
    final client = Client()
      ..responses.add(
        Response(302, '', location: 'https://evil.example/payload'),
      );
    await expectLater(
      GitHubReleaseSource(client: client).latest(app),
      throwsA(isA<UpdateFailure>()),
    );
    expect(client.urls.length, 1);
  });
  test('oversized metadata refused', () async {
    final client = Client()..responses.add(Response(200, 'a' * 1048577));
    await expectLater(
      GitHubReleaseSource(client: client).latest(app),
      throwsA(isA<UpdateFailure>()),
    );
  });
}
