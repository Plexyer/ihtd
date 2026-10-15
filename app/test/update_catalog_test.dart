import 'package:app/services/update_contract.dart';
import 'package:app/services/update_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> assets;
  final app = InstalledApp(
    Version.parse('0.2.3'),
    12,
    'android',
    'arm64',
    api: 35,
  );
  setUp(() {
    manifest = {
      'schema': 1,
      'tag': 'v0.2.4',
      'version': '0.2.4',
      'build': 13,
      'commit': 'a' * 40,
      'packages': [
        {
          'platform': 'android',
          'arch': 'arm64',
          'name': 'IHTD-0.2.4-android-arm64.apk',
          'minApi': 35,
          'packageId': 'dev.ihtd.app',
          'certificate': androidReleaseCertificate,
          'size': 100,
          'sha256': 'a' * 64,
        },
        {
          'platform': 'windows',
          'arch': 'x64',
          'name': 'IHTD-0.2.4-windows-x64-setup.exe',
          'size': 100,
          'sha256': 'b' * 64,
        },
        {
          'platform': 'fedora',
          'arch': 'x64',
          'distribution': 'fedora44',
          'name': 'ihtd-0.2.4-1.fc44.x86_64.rpm',
          'size': 100,
          'sha256': 'c' * 64,
        },
      ],
    };
    assets = [
      for (final p in manifest['packages'] as List)
        {'name': p['name'], 'size': 100, 'state': 'uploaded'},
    ];
  });
  UpdateCandidate? select() =>
      selectUpdate(manifest, assets, app, tag: 'v0.2.4', notes: 'Notes');
  test('complete matching metadata selects exact APK and derived URL', () {
    final c = select()!;
    expect(c.name, endsWith('arm64.apk'));
    expect(c.download.host, 'github.com');
    expect(c.download.path, contains('/releases/download/v0.2.4/'));
  });
  test('missing another platform blocks partially published release', () {
    assets.removeLast();
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('ambiguous assets rejected', () {
    assets.add(assets.first);
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('mismatched size rejected', () {
    assets.first['size'] = 999;
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('mismatched tag/schema/commit rejected', () {
    manifest['schema'] = 5;
    expect(select, throwsA(isA<UpdateFailure>()));
    manifest['schema'] = 1;
    manifest['commit'] = 'bad';
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('certificate mismatch rejected', () {
    manifest['packages'][0]['certificate'] = 'b' * 64;
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('wrong package ID rejected', () {
    manifest['packages'][0]['packageId'] = 'other.app';
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('unsupported API rejected', () {
    manifest['packages'][0]['minApi'] = 36;
    expect(select, throwsA(isA<UpdateFailure>()));
  });
  test('same or lower build not advertised', () {
    manifest['build'] = 12;
    expect(select(), isNull);
  });
  test('path traversal and oversized payload rejected', () {
    manifest['packages'][0]['name'] = '../private.apk';
    expect(select, throwsA(isA<UpdateFailure>()));
    manifest['packages'][0]['name'] = 'IHTD-0.2.4-android-arm64.apk';
    manifest['packages'][0]['size'] = 536870913;
    expect(select, throwsA(isA<UpdateFailure>()));
  });
}
