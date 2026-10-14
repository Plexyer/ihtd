import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/services/android_documents.dart';
import 'package:app/services/document_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AndroidDocuments documents;
  late String remote, filename, localPath;
  String? failure;
  bool unavailable = false;
  int writes = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<dynamic> provider(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    if (call.method == 'environment') {
      return {'appVersion': '0.2.2', 'build': 7, 'androidApi': 36};
    }
    if (call.method == 'localHash') {
      return File(args['path'] as String).readAsString();
    }
    if (unavailable) {
      throw PlatformException(
        code: 'unavailable',
        message: 'SECRET content://private/account/token',
      );
    }
    if (call.method == 'inspect') return {'name': filename, 'hash': remote};
    if (call.method == 'read') {
      return {'hash': remote, 'bytes': Uint8List.fromList(utf8.encode(remote))};
    }
    if (call.method == 'write') {
      writes++;
      if (failure != null) {
        throw PlatformException(
          code: failure!,
          message: 'SECRET note and private file',
        );
      }
      remote = await File(args['path'] as String).readAsString();
      return remote;
    }
    if (call.method == 'open' || call.method == 'create') return null;
    throw StateError('Unexpected method ${call.method}');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ihtd-saf-test-');
    remote = 'original';
    filename = 'Tasks.ihtd';
    failure = null;
    unavailable = false;
    writes = 0;
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, provider);
    documents = AndroidDocuments(supportDirectory: () async => directory);
    await documents.initialize();
    localPath = documents.freshPath();
    await File(localPath).writeAsString(remote);
    await documents.attach({
      'uri': 'content://test/1',
      'name': filename,
      'path': localPath,
      'hash': remote,
    });
  });
  tearDown(() async {
    await documents.diagnostics.flush();
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'stage verifies selected bytes and creates an independent working path',
    () async {
      final staged = await documents.stage({
        'uri': 'content://test/1',
        'name': filename,
      });
      expect(await File(staged['path'] as String).readAsString(), remote);
      expect(staged['path'], isNot(localPath));
      expect(staged['hash'], remote);
    },
  );
  test('rename with edits stays yellow through polling and restart, writes only on explicit confirmation', () async {
    filename = 'Renamed.ihtd';
    await documents.check();
    expect(documents.connection, DocumentConnection.renamed);
    expect(documents.explanation, contains('Contents are unchanged'));
    await File(localPath).writeAsString('edited');
    await documents.publish();
    expect(writes, 0);
    expect(documents.summary, 'Pending changes — not saved to file');
    expect(documents.severe, false);
    final restored = AndroidDocuments(supportDirectory: () async => directory);
    await restored.initialize();
    await restored.publish();
    expect(writes, 0);
    expect(restored.name, 'Tasks.ihtd');
    expect(await restored.confirm(), true);
    expect(writes, 1);
    expect(remote, 'edited');
    expect(restored.name, filename);
    expect(restored.pending, false);
    await restored.diagnostics.flush();
  });
  test(
    'rename plus external content change cannot be confirmed/overwritten',
    () async {
      filename = 'Renamed.ihtd';
      remote = 'external';
      await File(localPath).writeAsString('edited');
      await documents.publish();
      expect(documents.explanation, contains('Contents also changed'));
      expect(await documents.confirm(), false);
      expect(writes, 0);
      expect(remote, 'external');
    },
  );
  test('revoked access returns as a confirmation barrier, never an automatic retry', () async {
    unavailable = true;
    await documents.check();
    expect(documents.connection, DocumentConnection.unavailable);
    expect(documents.explanation, contains('may have been'));
    await File(localPath).writeAsString('edited');
    await documents.publish();
    expect(documents.pending, true);
    unavailable = false;
    await documents.publish();
    expect(documents.connection, DocumentConnection.reconnectRequired);
    expect(writes, 0);
    expect(await documents.confirm(), true);
    expect(remote, 'edited');
  });
  for (final code in ['write_failed', 'verification_failed']) {
    test('$code is red and does not retry through polling', () async {
      await File(localPath).writeAsString('edited');
      failure = code;
      await documents.publish();
      expect(documents.connection, DocumentConnection.saveFailed);
      expect(documents.severe, true);
      await documents.publish();
      expect(writes, 1);
      failure = null;
      expect(await documents.confirm(), true);
      expect(remote, 'edited');
    });
  }
  test(
    'partial write remains red and never silently overwrites corrupted content',
    () async {
      await File(localPath).writeAsString('edited');
      failure = 'verification_failed';
      await documents.publish();
      remote = 'partial';
      await documents.publish();
      expect(documents.severe, true);
      expect(writes, 1);
      expect(await documents.confirm(), false);
      expect(remote, 'partial');
      expect(documents.severe, true);
    },
  );
  test('same-name replacement with different bytes is not accepted', () async {
    await File(localPath).writeAsString('edited');
    remote = 'replacement';
    expect(
      await documents.confirm(
        selected: {'uri': 'content://test/2', 'name': filename, 'hash': remote},
      ),
      false,
    );
    expect(documents.binding!['uri'], 'content://test/1');
    expect(writes, 0);
  });
  test('explicit reconnect to exact baseline is allowed, a changed approval is rejected', () async {
    await File(localPath).writeAsString('edited');
    expect(
      await documents.confirm(
        selected: {
          'uri': 'content://test/2',
          'name': filename,
          'hash': 'stale approval',
        },
      ),
      false,
    );
    expect(writes, 0);
    expect(
      await documents.confirm(
        selected: {'uri': 'content://test/2', 'name': filename, 'hash': remote},
      ),
      true,
    );
    expect(documents.binding!['uri'], 'content://test/2');
    expect(remote, 'edited');
  });
  test('new edits during an in-flight save stay pending', () async {
    await File(localPath).writeAsString('first edit');
    final started = Completer<void>(), finish = Completer<void>();
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, (call) async {
      if (call.method == 'write') {
        final submitted = await File(localPath).readAsString();
        started.complete();
        await finish.future;
        remote = submitted;
        return submitted;
      }
      return provider(call);
    });
    final saving = documents.publish();
    await started.future;
    await File(localPath).writeAsString('second edit');
    finish.complete();
    await saving;
    expect(remote, 'first edit');
    expect(documents.pending, true);
    expect(documents.summary, 'Pending changes — not saved to file');
  });
  test(
    'restart with unpublished edits requires explicit confirmation',
    () async {
      await File(localPath).writeAsString('edited');
      final restored = AndroidDocuments(
        supportDirectory: () async => directory,
      );
      await restored.initialize();
      await restored.publish();
      expect(restored.connection, DocumentConnection.reconnectRequired);
      expect(writes, 0);
      await restored.diagnostics.flush();
    },
  );
  test('archived working copies retain their own URI and contents across switching', () async {
    filename = 'Renamed.ihtd';
    await File(localPath).writeAsString('edited');
    await documents.check();
    await documents.archive();
    final other = documents.freshPath();
    await File(other).writeAsString(remote);
    await documents.attach({
      'uri': 'content://test/2',
      'name': filename,
      'path': other,
      'hash': remote,
    });
    final saved = await documents.retainedCollections();
    expect(saved.single['uri'], 'content://test/1');
    expect(saved.single['pending'], true);
    expect(await File(saved.single['path'] as String).readAsString(), 'edited');
    expect(writes, 0);
  });
  test(
    'metadata disk failure blocks publishing and never uses the previous URI',
    () async {
      final blocker = Directory('${documents.directory.path}/active.json.tmp');
      await blocker.create();
      final next = documents.freshPath();
      await File(next).writeAsString('edited');
      await documents.attach({
        'uri': 'content://test/2',
        'name': filename,
        'path': next,
        'hash': remote,
      });
      expect(documents.binding!['uri'], 'content://test/2');
      expect(documents.severe, true);
      await documents.publish();
      expect(writes, 0);
      await blocker.delete();
      expect(await documents.confirm(), true);
      expect(remote, 'edited');
    },
  );
  test(
    'unknown provider name is not invented and prevents publication',
    () async {
      await File(localPath).writeAsString('edited');
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        if (call.method == 'inspect') return {'name': null, 'hash': remote};
        return provider(call);
      });
      await documents.publish();
      expect(documents.connection, DocumentConnection.unavailable);
      expect(writes, 0);
    },
  );

  test('copy destination with existing content is never overwritten', () async {
    await expectLater(
      documents.copyTo({'uri': 'content://test/2'}, localPath),
      throwsStateError,
    );
    expect(writes, 0);
  });
  test('default diagnostics omit injected secrets, filenames, identifiers and content', () async {
    unavailable = true;
    await documents.check();
    final output = documents.diagnostics.export(
      state: 'unavailable',
      pending: false,
    );
    for (final forbidden in [
      'SECRET',
      'content://',
      filename,
      localPath,
      'original',
      'token',
    ]) {
      expect(output, isNot(contains(forbidden)));
    }
    expect(jsonDecode(output)['environment']['appVersion'], '0.2.2');
    final extended = documents.diagnostics.export(
      state: 'unavailable',
      pending: false,
      extended: {'name': filename},
    );
    expect(extended, contains(filename));
  });
  test('actual log export works with unavailable source and leaves pending edits untouched', () async {
    await File(localPath).writeAsString('PRIVATE NOTE');
    unavailable = true;
    await documents.check();
    String? output;
    messenger.setMockMethodCallHandler(AndroidDocuments.channel, (call) async {
      if (call.method == 'create') {
        return {'uri': 'content://logs/1', 'name': 'diagnostics.json'};
      }
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      if (args['uri'] == 'content://logs/1') {
        if (call.method == 'read') {
          return {'bytes': Uint8List(0), 'hash': 'empty'};
        }
        if (call.method == 'write') {
          output = await File(args['path'] as String).readAsString();
          return output;
        }
      }
      return provider(call);
    });
    await documents.exportDiagnostics();
    expect(jsonDecode(output!)['formatVersion'], 1);
    expect(output, isNot(contains('PRIVATE NOTE')));
    expect(output, isNot(contains('content://')));
    expect(output, isNot(contains(filename)));
    expect(documents.pending, true);
    expect(documents.connection, DocumentConnection.unavailable);
    expect(documents.binding!['uri'], 'content://test/1');
    await documents.exportDiagnostics(extended: true);
    expect(output, contains(filename));
    expect(output, isNot(contains('content://')));
    expect(output, isNot(contains('PRIVATE NOTE')));
  });

  test('logs remain bounded and reject arbitrary exception text', () {
    final diagnostics = DocumentDiagnostics();
    diagnostics.record('SECRET content://private', true);
    diagnostics.record('secret_key', true);
    for (var i = 0; i < 300; i++) {
      diagnostics.record(i.isEven ? 'connected' : 'unavailable', i.isEven);
    }
    expect(diagnostics.events.length, 120);
    expect(
      diagnostics.export(state: 'connected', pending: false),
      isNot(contains('SECRET')),
    );
  });
}
