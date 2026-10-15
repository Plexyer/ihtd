import 'package:pub_semver/pub_semver.dart';

const updateRepository = 'Plexyer/ihtd';
const androidReleaseCertificate =
    'bea383d80c5134b0bfb8515aaa45afb15a4838540f9006ba3080ad402c7a01f4';

class UpdateFailure implements Exception {
  const UpdateFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

class InstalledApp {
  const InstalledApp(
    this.version,
    this.build,
    this.platform,
    this.arch, {
    this.api = 0,
  });
  final Version version;
  final int build;
  final String platform, arch;
  final int api;
}

class UpdateCandidate {
  const UpdateCandidate({
    required this.version,
    required this.build,
    required this.tag,
    required this.notes,
    required this.name,
    required this.size,
    required this.sha256,
    required this.platform,
  });
  final String version, tag, notes, name, sha256, platform;
  final int build, size;
  Uri get page =>
      Uri.https('github.com', '/$updateRepository/releases/tag/$tag');
  Uri get download => Uri.https(
    'github.com',
    '/$updateRepository/releases/download/$tag/$name',
  );
  Map<String, dynamic> toJson() => {
    'version': version,
    'build': build,
    'tag': tag,
    'notes': notes,
    'name': name,
    'size': size,
    'sha256': sha256,
    'platform': platform,
  };
  factory UpdateCandidate.fromJson(Map<String, dynamic> j) {
    final v = Version.parse(j['version'] as String);
    final name = j['name'] as String;
    final platform = j['platform'] as String;
    final expected = switch (platform) {
      'android' => 'IHTD-$v-android-arm64.apk',
      'windows' => 'IHTD-$v-windows-x64-setup.exe',
      'fedora' => 'ihtd-$v-1.fc44.x86_64.rpm',
      _ => throw const UpdateFailure('unsupported_device'),
    };
    if (v.isPreRelease ||
        v.build.isNotEmpty ||
        j['tag'] != 'v$v' ||
        name != expected ||
        j['build'] is! int ||
        (j['build'] as int) <= 0 ||
        j['size'] is! int ||
        (j['size'] as int) <= 0 ||
        (j['size'] as int) > 536870912 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(j['sha256'] as String)) {
      throw const UpdateFailure('invalid_metadata');
    }
    return UpdateCandidate(
      version: '$v',
      build: j['build'] as int,
      tag: j['tag'] as String,
      notes: (j['notes'] as String).substring(
        0,
        (j['notes'] as String).length.clamp(0, 6000),
      ),
      name: name,
      size: j['size'] as int,
      sha256: j['sha256'] as String,
      platform: platform,
    );
  }
  bool newerThan(InstalledApp app) =>
      platform == app.platform &&
      Version.parse(version) > app.version &&
      (platform != 'android' || build > app.build);
}

abstract interface class ReleaseSource {
  Future<UpdateCandidate?> latest(InstalledApp app);
}

class DownloadObservation {
  const DownloadObservation(this.state, this.bytes, this.total);
  final String state;
  final int bytes, total;
}

abstract interface class UpdatePlatform {
  Future<InstalledApp> identity();
  bool get canInstall;
  Future<void> start(UpdateCandidate candidate);
  Future<DownloadObservation> observe();
  Future<void> verify(UpdateCandidate candidate);

  /// Returns permission when system settings were opened, or installer.
  Future<String> install(UpdateCandidate candidate);
  Future<void> cancel();
  Future<void> openRelease(UpdateCandidate candidate);
}
