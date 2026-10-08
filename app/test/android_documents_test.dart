import 'dart:io';

import 'package:app/services/android_documents.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AndroidDocuments documents;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ihtd-saf-test-');
    documents = AndroidDocuments(supportDirectory: () async => directory);
    await documents.initialize();
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'stages provider bytes privately and restores binding after restart',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidDocuments.channel,
        (call) async => {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'hash': 'original',
        },
      );
      final staged = await documents.stage({
        'uri': 'content://test/1',
        'name': 'Tasks.ihtd',
      });
      expect(await File(staged['path'] as String).readAsBytes(), [1, 2, 3]);
      expect(staged['path'], isNot(staged['uri']));
      await documents.remember(staged);
      final restored = AndroidDocuments(
        supportDirectory: () async => directory,
      );
      expect(await restored.initialize(), staged);
      expect(restored.name, 'Tasks.ihtd');
    },
  );

  test(
    'failed publication preserves local file and expected provider hash',
    () async {
      final path = documents.freshPath();
      await File(path).writeAsString('pending edit');
      await documents.remember({
        'uri': 'content://test/1',
        'path': path,
        'hash': 'original',
      });
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        throw PlatformException(code: 'document', message: 'access revoked');
      });
      await expectLater(documents.publish(), throwsA(isA<PlatformException>()));
      expect(await File(path).readAsString(), 'pending edit');
      final restored = AndroidDocuments(
        supportDirectory: () async => directory,
      );
      expect((await restored.initialize())!['hash'], 'original');
    },
  );

  test('confirmed publication persists updated hash', () async {
    await documents.remember({
      'uri': 'content://test/1',
      'path': documents.freshPath(),
      'hash': 'original',
    });
    messenger.setMockMethodCallHandler(
      AndroidDocuments.channel,
      (call) async => 'saved',
    );
    await documents.publish();
    final restored = AndroidDocuments(supportDirectory: () async => directory);
    expect((await restored.initialize())!['hash'], 'saved');
  });

  test(
    'failed binding metadata write never points edits at the old document',
    () async {
      await documents.remember({
        'uri': 'content://test/old',
        'path': documents.freshPath(),
        'hash': 'old',
      });
      final blockingDirectory = Directory(
        '${documents.directory.path}/active.json.tmp',
      );
      await blockingDirectory.create();
      final next = {
        'uri': 'content://test/new',
        'path': documents.freshPath(),
        'hash': 'new',
      };
      await expectLater(
        documents.remember(next),
        throwsA(isA<FileSystemException>()),
      );
      expect(documents.binding, next);
      await blockingDirectory.delete();
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        expect(call.arguments['uri'], 'content://test/new');
        return 'new';
      });
      await documents.publish();
      final restored = AndroidDocuments(
        supportDirectory: () async => directory,
      );
      expect(await restored.initialize(), next);
    },
  );

  test('save-copy refuses a destination that already contains data', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, (call) async {
      calls.add(call.method);
      return {
        'bytes': Uint8List.fromList([7]),
        'hash': 'existing',
      };
    });
    await expectLater(
      documents.copyTo({
        'uri': 'content://test/existing',
      }, documents.freshPath()),
      throwsStateError,
    );
    expect(calls, ['read']);
  });

  test(
    'pending changes must publish before switching; clean files can reopen',
    () async {
      await documents.remember({
        'uri': 'content://test/1',
        'path': documents.freshPath(),
        'hash': 'original',
      });
      var pending = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'pending') return pending;
        throw PlatformException(code: 'document', message: 'conflict');
      });
      await documents.checkBeforeSwitch();
      expect(calls, ['pending']);
      pending = true;
      await expectLater(
        documents.checkBeforeSwitch(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['pending', 'pending', 'write']);
    },
  );
}
