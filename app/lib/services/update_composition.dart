import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_contract.dart';
import 'update_catalog.dart';
import 'update_coordinator.dart';

final updateProvider = ChangeNotifierProvider<UpdateCoordinator>((ref) {
  final source = GitHubReleaseSource();
  ref.onDispose(source.close);
  return UpdateCoordinator(
    source: source,
    platform: Platform.isAndroid ? AndroidUpdates() : DesktopUpdates(),
    stateFile: () async => File(
      '${(await getApplicationSupportDirectory()).path}/updates/state.json',
    ),
  );
});

class AndroidUpdates implements UpdatePlatform {
  static const channel = MethodChannel('dev.ihtd.app/updates');
  Future<T?> _call<T>(String method, [UpdateCandidate? c]) async {
    try {
      return await channel.invokeMethod<T>(method, c?.toJson());
    } on PlatformException catch (e) {
      throw UpdateFailure(e.code);
    }
  }

  @override
  bool get canInstall => true;
  @override
  Future<InstalledApp> identity() async {
    final j = (await _call<Map>('identity'))!;
    return InstalledApp(
      Version.parse(j['version'] as String),
      j['build'] as int,
      'android',
      j['arch'] as String,
      api: j['api'] as int,
    );
  }

  @override
  Future<void> start(UpdateCandidate c) async {
    await _call<void>('download', c);
  }

  @override
  Future<DownloadObservation> observe() async {
    final j = (await _call<Map>('observe'))!;
    return DownloadObservation(
      j['state'] as String,
      j['bytes'] as int,
      j['total'] as int,
    );
  }

  @override
  Future<void> verify(UpdateCandidate c) async {
    await _call<void>('verify', c);
  }

  @override
  Future<String> install(UpdateCandidate c) async =>
      (await _call<String>('install', c))!;
  @override
  Future<void> cancel() async {
    await _call<void>('cancel');
  }

  @override
  Future<void> openRelease(UpdateCandidate c) async {
    if (!await launchUrl(c.page, mode: LaunchMode.externalApplication)) {
      throw const UpdateFailure('browser');
    }
  }
}

/// Unsigned desktop installers must not be silently promoted to trusted install.
/// The same release discovery/UI is used, with an explicit manual handoff.
class DesktopUpdates implements UpdatePlatform {
  @override
  bool get canInstall => false;
  @override
  Future<InstalledApp> identity() async {
    final info = await PackageInfo.fromPlatform();
    final arch =
        Abi.current() == Abi.linuxX64 || Abi.current() == Abi.windowsX64
        ? 'x64'
        : 'unsupported';
    var platform = Platform.isWindows ? 'windows' : 'unsupported';
    if (Platform.isLinux) {
      final release = File('/etc/os-release');
      if (await release.exists()) {
        final values = <String, String>{};
        for (final line in await release.readAsLines()) {
          final split = line.indexOf('=');
          if (split > 0) {
            values[line.substring(0, split)] = line
                .substring(split + 1)
                .replaceAll('"', '');
          }
        }
        if (values['ID'] == 'fedora' && values['VERSION_ID'] == '44') {
          platform = 'fedora';
        }
      }
    }
    return InstalledApp(
      Version.parse(info.version),
      int.tryParse(info.buildNumber) ?? 0,
      platform,
      arch,
    );
  }

  @override
  Future<void> openRelease(UpdateCandidate c) async {
    if (!await launchUrl(c.page, mode: LaunchMode.externalApplication)) {
      throw const UpdateFailure('browser');
    }
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> start(UpdateCandidate c) async {
    throw const UpdateFailure('unsupported_device');
  }

  @override
  Future<DownloadObservation> observe() async =>
      const DownloadObservation('missing', 0, 0);
  @override
  Future<void> verify(UpdateCandidate c) async {
    throw const UpdateFailure('verification');
  }

  @override
  Future<String> install(UpdateCandidate c) async =>
      throw const UpdateFailure('unsupported_device');
}
