import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/services/update_contract.dart';
import 'package:app/services/update_coordinator.dart';
import 'package:app/ui/app_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

final installed = InstalledApp(
  Version.parse('0.2.3'),
  12,
  'android',
  'arm64',
  api: 35,
);
UpdateCandidate candidate([String version = '0.2.4', int build = 13]) =>
    UpdateCandidate.fromJson({
      'version': version,
      'build': build,
      'tag': 'v$version',
      'notes': 'Release notes',
      'name': 'IHTD-$version-android-arm64.apk',
      'size': 100,
      'sha256': 'a' * 64,
      'platform': 'android',
    });

class Source implements ReleaseSource {
  int calls = 0;
  UpdateCandidate? value = candidate();
  Object? failure;
  @override
  Future<UpdateCandidate?> latest(InstalledApp app) async {
    calls++;
    if (failure != null) throw failure!;
    return value;
  }
}

class Adapter implements UpdatePlatform {
  bool failVerify = false;
  int starts = 0, verifications = 0, installs = 0, cancellations = 0;
  DownloadObservation observation = const DownloadObservation(
    'downloading',
    20,
    100,
  );
  String result = 'installer';
  bool failInstall = false;
  Completer<void>? startGate;
  @override
  bool get canInstall => true;
  @override
  Future<InstalledApp> identity() async => installed;
  @override
  Future<void> start(UpdateCandidate c) async {
    starts++;
    await startGate?.future;
  }

  @override
  Future<DownloadObservation> observe() async => observation;
  @override
  Future<void> verify(UpdateCandidate c) async {
    verifications++;
    if (failVerify) throw const UpdateFailure('verification');
  }

  @override
  Future<String> install(UpdateCandidate c) async {
    installs++;
    if (failInstall) throw const UpdateFailure('installer');
    return result;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> openRelease(UpdateCandidate c) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Source source;
  late Adapter adapter;
  late UpdateCoordinator u;
  var disposed = false;
  setUp(() async {
    disposed = false;
    dir = await Directory.systemTemp.createTemp('ihtd-update-test-');
    source = Source();
    adapter = Adapter();
    u = UpdateCoordinator(
      source: source,
      platform: adapter,
      stateFile: () async => File('${dir.path}/updates.json'),
    );
    await u.ready;
  });
  tearDown(() async {
    if (!disposed) u.dispose();
    await dir.delete(recursive: true);
  });
  test('semantic comparison and Android build both prevent downgrades', () {
    expect(candidate('0.2.10').newerThan(installed), isTrue);
    expect(candidate('0.2.4', 11).newerThan(installed), isFalse);
    expect(candidate('0.2.3', 13).newerThan(installed), isFalse);
    expect(() => candidate('../bad'), throwsA(anything));
  });
  test('automatic checks back off; manual check bypasses interval', () async {
    expect(source.calls, 1);
    await u.check(manual: false);
    expect(source.calls, 1);
    await u.check();
    expect(source.calls, 2);
    await u.setAutomatic(false);
    await u.check(manual: false);
    expect(source.calls, 2);
  });
  test('offline check retains known candidate and useful error', () async {
    source.failure = const UpdateFailure('offline');
    await u.check();
    expect(u.candidate, isNotNull);
    expect(u.phase, UpdatePhase.available);
    expect(u.message, contains('offline'));
  });
  test(
    'only verified package becomes ready; reverify before installation',
    () async {
      await u.download();
      await u.poll();
      expect(u.progress, .2);
      expect(u.phase, UpdatePhase.downloading);
      adapter.observation = const DownloadObservation('complete', 100, 100);
      await u.poll();
      expect(u.phase, UpdatePhase.ready);
      expect(adapter.verifications, 1);
      await u.install(() async => true);
      expect(adapter.verifications, 2);
      expect(adapter.installs, 1);
      expect(u.phase, UpdatePhase.ready); // handoff is not installation success
    },
  );
  test('tampering never becomes ready', () async {
    adapter.failVerify = true;
    adapter.observation = const DownloadObservation('complete', 100, 100);
    await u.download();
    await u.poll();
    expect(u.phase, UpdatePhase.error);
    expect(adapter.cancellations, 1);
    expect(u.message, contains('verification failed'));
    expect(adapter.installs, 0);
  });
  test('invalid drafts block handoff; system permission keeps ready', () async {
    adapter.observation = const DownloadObservation('complete', 100, 100);
    await u.download();
    await u.poll();
    await u.install(() async => false);
    expect(adapter.installs, 0);
    adapter.result = 'permission';
    await u.install(() async => true);
    expect(u.phase, UpdatePhase.ready);
    expect(u.message, contains('settings'));
  });
  test(
    'system installer failure retains verified ready package for retry',
    () async {
      adapter.observation = const DownloadObservation('complete', 100, 100);
      await u.download();
      await u.poll();
      adapter.failInstall = true;
      await u.install(() async => true);
      expect(u.phase, UpdatePhase.ready);
      expect(u.message, contains('system installer'));
      adapter.failInstall = false;
      await u.install(() async => true);
      expect(adapter.starts, 1);
      expect(adapter.installs, 2);
    },
  );
  test('duplicate user taps cannot enqueue simultaneous downloads', () async {
    adapter.startGate = Completer<void>();
    final first = u.download();
    await Future<void>.delayed(Duration.zero);
    await u.download();
    adapter.startGate!.complete();
    await first;
    expect(adapter.starts, 1);
  });
  test(
    'failed native download clears unsafe file and supports retry',
    () async {
      adapter.observation = const DownloadObservation('failed', 12, 100);
      await u.download();
      await u.poll();
      expect(u.phase, UpdatePhase.error);
      expect(adapter.cancellations, 1);
      await u.download();
      expect(adapter.starts, 2);
    },
  );
  test('restarting verifies completed cached download afresh', () async {
    adapter.observation = const DownloadObservation('complete', 100, 100);
    await u.download();
    await u.poll();
    final restarted = UpdateCoordinator(
      source: source,
      platform: adapter,
      stateFile: () async => File('${dir.path}/updates.json'),
    );
    await restarted.ready;
    expect(restarted.phase, UpdatePhase.ready);
    expect(adapter.verifications, 2);
    restarted.dispose();
  });
  test(
    'persisted ready flag alone cannot make a missing download ready',
    () async {
      await u.download();
      adapter.observation = const DownloadObservation('missing', 0, 0);
      final restarted = UpdateCoordinator(
        source: source,
        platform: adapter,
        stateFile: () async => File('${dir.path}/updates.json'),
      );
      await restarted.ready;
      expect(restarted.phase, UpdatePhase.error);
      restarted.dispose();
    },
  );
  test('current-version restart drops stale candidate and cache', () async {
    await File('${dir.path}/updates.json').writeAsString(
      jsonEncode({
        'candidate': candidate('0.2.3', 12).toJson(),
        'download': true,
        'automatic': false,
      }),
    );
    final restarted = UpdateCoordinator(
      source: source,
      platform: adapter,
      stateFile: () async => File('${dir.path}/updates.json'),
    );
    await restarted.ready;
    expect(restarted.candidate, isNull);
    expect(adapter.cancellations, 1);
    expect(restarted.automatic, isFalse);
    restarted.dispose();
  });
  testWidgets(
    'download confirmation closes popup before starting native work',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showUpdateDetails(context, u),
                child: const Text('Updates'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Release notes'), findsOneWidget);
      expect(adapter.starts, 0);
      await tester.runAsync(() async {
        await tester.tap(find.text('Download'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      for (var i = 0; i < 50 && adapter.starts == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(adapter.starts, 1, reason: '${u.phase}: ${u.message}');
      u.dispose();
      disposed = true;
    },
  );
  testWidgets('reduced motion is static, state has accessible install label', (
    tester,
  ) async {
    await tester.runAsync(u.download);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: UpdateIndicator(updates: u, onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // must settle while download is still active
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    u.phase = UpdatePhase.ready;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateIndicator(updates: u, onPressed: () {}),
        ),
      ),
    );
    expect(find.byTooltip('Install update'), findsOneWidget);
  });
}
