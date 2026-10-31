import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/services/document_adapter.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/migration_contract.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List documentBytes(int version, [String text = 'Private task text']) {
  final bytes = Uint8List(100 + utf8.encode(text).length);
  bytes.setRange(0, 16, utf8.encode('SQLite format 3\u0000'));
  ByteData.sublistView(bytes).setUint32(60, version);
  bytes.setRange(100, bytes.length, utf8.encode(text));
  return bytes;
}

String digest(List<int> bytes) => base64Encode(bytes);

/// Deliberately separate fake native storage from fake pure migration engine.
/// Tests verify shared ordering/barriers, not SQLite's implementation.
class MigrationAdapter implements DocumentAdapter, MigrationBackupAdapter {
  MigrationAdapter(this.kind);
  @override
  final String kind;
  @override
  List<String> get legacyRegistryNames => [];
  @override
  bool get backupFolderRequired => kind == 'android';
  String name = 'Private collection.ihtd', identity = 'file-one';
  Uint8List remote = documentBytes(1);
  final Map<String, Uint8List> backups = {};
  final List<String> events = [];
  bool cancelFolder = false,
      denyBackup = false,
      corruptBackup = false,
      writeFails = false;
  bool partialWrite = false, unavailable = false, writeThenFail = false;
  int publications = 0;
  @override
  DocumentReference referenceFor(String locator) =>
      DocumentReference(kind, locator);
  @override
  Future<Map<String, dynamic>> environment() async => {
    'appVersion': '0.2.5',
    'build': 14,
    'os': 'test',
  };
  @override
  Future<DocumentReference?> pick({String? suggested}) async => null;
  @override
  Future<DocumentReference?> pickBackupFolder() async {
    events.add('authorize');
    return cancelFolder ? null : referenceFor('authorized-folder');
  }

  @override
  Future<DocumentReference> createMigrationBackup({
    required DocumentReference source,
    required String snapshotPath,
    required String name,
    DocumentReference? folder,
  }) async {
    events.add('backup');
    if (denyBackup) {
      throw const DocumentFailure(DocumentFailureKind.writeFailed);
    }
    if (backupFolderRequired && folder == null) {
      throw StateError('Missing authorization');
    }
    final reference = referenceFor('backup-${backups.length}');
    backups[reference.locator] = await File(snapshotPath).readAsBytes();
    return reference;
  }

  @override
  Future<DocumentRead> read(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async {
    if (unavailable) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    var bytes = backups[reference.locator] ?? remote;
    if (backups.containsKey(reference.locator)) {
      events.add('verifyBackup');
      if (corruptBackup) bytes = documentBytes(1, 'broken');
    }
    return DocumentRead(bytes, digest(bytes));
  }

  @override
  Future<DocumentObservation> inspect(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async =>
      DocumentObservation(hash: digest(remote), name: name, identity: identity);
  @override
  Future<String> localHash(String path) async =>
      digest(await File(path).readAsBytes());
  @override
  Future<DocumentObservation> publish(
    DocumentReference reference,
    String workingPath, {
    required String expectedHash,
    String? expectedName,
    String? expectedIdentity,
    bool create = false,
  }) async {
    publications++;
    events.add('publish');
    if (expectedHash != digest(remote) ||
        expectedName != name ||
        expectedIdentity != identity) {
      throw const DocumentFailure(DocumentFailureKind.externalChanged);
    }
    if (writeFails) {
      throw const DocumentFailure(DocumentFailureKind.writeFailed);
    }
    if (partialWrite) {
      remote = Uint8List.fromList([1, 2, 3]);
      throw const DocumentFailure(DocumentFailureKind.verificationFailed);
    }
    remote = await File(workingPath).readAsBytes();
    if (writeThenFail) {
      throw const DocumentFailure(DocumentFailureKind.verificationFailed);
    }
    identity = 'published-$publications';
    return inspect(reference);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['filesystem', 'android']) {
    group('$kind migration safety', () {
      late Directory temp;
      late MigrationAdapter adapter;
      late DocumentSaveCoordinator storage;
      String? engineFailure;
      int preparations = 0;
      bool semantic = false;
      Future<String> engine(String request) async {
        final command = jsonDecode(request) as Map;
        final bytes = await File(command['source'] as String).readAsBytes();
        final version = ByteData.sublistView(bytes).getUint32(60);
        if (command['action'] == 'probe') {
          return jsonEncode({
            'ok': true,
            'data': {
              'needed': version != 2 || (semantic && bytes[99] == 0),
              'plan': semantic ? 'protected-all-tasks' : 'schema-1-to-2',
              'from': version,
              'target': 2,
              'hash': digest(bytes),
            },
          });
        }
        adapter.events.add('prepare');
        preparations++;
        if (engineFailure != null) {
          return jsonEncode({'ok': false, 'error_code': engineFailure});
        }
        if (digest(bytes) != command['expected_hash']) {
          throw StateError('Stale candidate');
        }
        final candidate = Uint8List.fromList(bytes);
        ByteData.sublistView(candidate).setUint32(60, 2);
        if (semantic) candidate[99] = 1;
        await File(command['candidate'] as String)
            .writeAsBytes(candidate, flush: true);
        return jsonEncode({
          'ok': true,
          'data': {'validated': true, 'hash': digest(candidate)},
        });
      }

      Future<Map<String, dynamic>> stage() => storage.stage({
        'reference': adapter.referenceFor('source').toJson(),
        'name': adapter.name,
      });
      setUp(() async {
        temp = await Directory.systemTemp.createTemp('ihtd-migration-');
        adapter = MigrationAdapter(kind);
        engineFailure = null;
        preparations = 0;
        semantic = false;
        storage = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => temp,
        );
        storage.migrations.command = engine;
        await storage.initialize();
      });
      tearDown(() async {
        await storage.diagnostics.flush();
        await temp.delete(recursive: true);
      });
      test('backup read-back precedes conversion; publish is guarded and backup remains original', () async {
        final original = Uint8List.fromList(adapter.remote);
        final prepared = await stage();
        expect(adapter.remote, original);
        expect(
          adapter.events.indexOf('verifyBackup'),
          lessThan(adapter.events.indexOf('prepare')),
        );
        expect(adapter.backups.values.single, original);
        await storage.attach(prepared);
        await storage.publish();
        expect(storage.pending, false);
        expect(storage.connection, DocumentConnection.connected);
        expect(adapter.publications, 1);
        expect(ByteData.sublistView(adapter.remote).getUint32(60), 2);
        expect(adapter.backups.values.single, original);
        final jobs = await storage.migrations.recoveryAttempts();
        expect(jobs.single['status'], 'completed');
        expect(
          await File((jobs.single['original'] as Map)['path'] as String)
              .readAsBytes(),
          original,
        );
      });
      test('same-schema semantic upgrades require verified backups and preserve draft-owner evidence', () async {
        semantic = true;
        adapter.remote = documentBytes(2);
        final original = Uint8List.fromList(adapter.remote);
        final prepared = await stage();
        expect(preparations, 1);
        expect(
          adapter.events.indexOf('verifyBackup'),
          lessThan(adapter.events.indexOf('prepare')),
        );
        expect(adapter.backups.values.single, original);
        final job = (await storage.migrations.recoveryAttempts()).single;
        expect(job['from'], 2);
        expect(job['target'], 2);
        final old = (job['original'] as Map)['path'] as String;
        final current = prepared['path'] as String;
        expect(
          await storage.migrations.preservesDraftOwner(old, current),
          true,
        );
        expect(
          await storage.migrations.preservesDraftOwner(
            '$old-unrelated',
            current,
          ),
          false,
        );
        expect(
          await storage.migrations.preservesDraftOwner(old, '$current-copy'),
          false,
        );
        await storage.attach(prepared);
        await storage.publish();
        expect(adapter.remote[99], 1);
        expect(adapter.backups.values.single, original);
        await File(old).writeAsBytes(documentBytes(2, 'changed'));
        expect(
          await storage.migrations.preservesDraftOwner(old, current),
          false,
        );
      });
      for (final failure in ['denied', 'corrupt', 'candidate']) {
        test(
          'semantic upgrade $failure preserves source and records failure',
          () async {
            semantic = true;
            adapter.remote = documentBytes(2);
            adapter.denyBackup = failure == 'denied';
            adapter.corruptBackup = failure == 'corrupt';
            engineFailure = failure == 'candidate' ? 'validation_failed' : null;
            final original = Uint8List.fromList(adapter.remote);
            await expectLater(stage(), throwsA(isA<MigrationFailure>()));
            expect(adapter.remote, original);
            expect(adapter.publications, 0);
            expect(preparations, failure == 'candidate' ? 1 : 0);
            final log = jsonDecode(await storage.migrations.exportLog());
            expect(log['sourceFormat'], 2);
            expect(log['plans'], ['protected-all-tasks']);
          },
        );
      }
      test('current distributed format makes no migration, backup or authorization request', () async {
        adapter.remote = documentBytes(2);
        final prepared = await stage();
        expect(prepared['migrationAttempt'], null);
        expect(adapter.backups, isEmpty);
        expect(preparations, 0);
        expect(adapter.events, isEmpty);
      });
      for (final failure in ['denied', 'corrupt', 'candidate']) {
        test(
          '$failure stops before external modification and automatically saves redacted log',
          () async {
            adapter.denyBackup = failure == 'denied';
            adapter.corruptBackup = failure == 'corrupt';
            engineFailure = failure == 'candidate' ? 'validation_failed' : null;
            final original = Uint8List.fromList(adapter.remote);
            await expectLater(stage(), throwsA(isA<MigrationFailure>()));
            expect(adapter.remote, original);
            expect(adapter.publications, 0);
            expect(preparations, failure == 'candidate' ? 1 : 0);
            final log = await storage.migrations.exportLog();
            expect(log, contains('"code":'));
            for (final secret in [
              'Private task',
              'Private collection',
              temp.path,
              'source',
              'authorized-folder',
            ]) {
              // "sourceFormat" is an allowed key, but locations/contents are not.
              if (secret != 'source') expect(log, isNot(contains(secret)));
            }
            expect(storage.migrations.logFailed, false);
          },
        );
      }
      test('interruption records failure on restart and never republishes; safe retry retains earlier backup', () async {
        final first = await stage();
        final firstBackup = Uint8List.fromList(adapter.backups.values.first);
        final restart = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => temp,
        );
        restart.migrations.command = engine;
        await restart.initialize();
        expect(restart.migrations.issue?['failure'], 'interrupted');
        expect(
          restart.severe,
          false,
          reason: 'interruption before publication left the original untouched',
        );
        expect(await restart.migrations.exportLog(), contains('interrupted'));
        expect(adapter.publications, 0);
        final interrupted =
            (await restart.migrations.recoveryAttempts()).single;
        await expectLater(
          restart.migrations.prepare(
            Map<String, dynamic>.from(interrupted['original']),
            retained: true,
            automatic: true,
          ),
          throwsA(isA<MigrationFailure>()),
        );
        expect(
          adapter.backups.length,
          1,
          reason:
              'restart cannot begin another backup/conversion automatically',
        );
        expect(preparations, 1);
        expect((await restart.migrations.recoveryAttempts()).length, 1);
        final second = await restart.stage({
          'reference': adapter.referenceFor('source').toJson(),
          'name': adapter.name,
        });
        expect(second['migrationAttempt'], isNot(first['migrationAttempt']));
        await restart.attach(second);
        await restart.publish();
        expect(adapter.publications, 1);
        expect(restart.migrations.hasIssue, false);
        expect(adapter.backups.length, 2);
        expect(adapter.backups.values.first, firstBackup);
        await restart.diagnostics.flush();
      });
      test('changed identity before publication is not overwritten and produces failure log', () async {
        final prepared = await stage();
        adapter.identity = 'replacement';
        await storage.attach(prepared);
        await storage.publish();
        expect(adapter.publications, 0);
        expect(storage.migrations.issue?['failure'], 'publication_failed');
        expect(storage.connection, DocumentConnection.replaced);
        expect(
          await storage.migrations.exportLog(),
          contains('publication_failed'),
        );
      });
      test('partial provider write stays blocked across confirm and restart; backup and candidate survive', () async {
        final prepared = await stage();
        await storage.attach(prepared);
        adapter.partialWrite = true;
        await storage.publish();
        expect(storage.severe, true);
        expect(adapter.backups, isNotEmpty);
        expect(await File(prepared['path'] as String).exists(), true);
        expect(await storage.confirm(), false);
        expect(adapter.publications, 1);
        final restart = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => temp,
        );
        restart.migrations.command = engine;
        await restart.initialize();
        await restart.publish();
        expect(adapter.publications, 1);
        expect(restart.migrations.hasIssue, true);
        await restart.diagnostics.flush();
      });
      test('explicit reopen reconciles an already published exact candidate without another write', () async {
        final prepared = await stage();
        await storage.attach(prepared);
        adapter.writeThenFail = true;
        await storage.publish();
        expect(storage.migrations.hasIssue, true);
        expect(adapter.publications, 1);
        final reopened = await stage();
        expect(storage.migrations.hasIssue, false);
        expect(reopened['migrationAttempt'], null);
        expect(adapter.publications, 1);
        expect(adapter.backups.length, 1);
        final retained = await storage.migrations.prepare(
          prepared,
          retained: true,
        );
        expect(retained['migrationAttempt'], null);
        expect(
          (await storage.migrations.recoveryAttempts()).single['status'],
          'resolved',
        );
      });
      test('retained unpublished working and recovery states get distinct backups and candidates', () async {
        final working = storage.freshPath();
        final recovery = '$working.recovery';
        await File(working).writeAsBytes(documentBytes(1, 'unpublished'));
        await File(recovery).writeAsBytes(documentBytes(1, 'newest recovery'));
        final record = {
          'reference': adapter.referenceFor('source').toJson(),
          'name': adapter.name,
          'hash': digest(adapter.remote),
          'identity': adapter.identity,
          'path': working,
          'recoveryPath': recovery,
          'localDirty': true,
        };
        final prepared = await storage.migrations.prepare(
          record,
          retained: true,
        );
        expect(adapter.backups.length, 3);
        expect(preparations, 2);
        expect(prepared['path'], isNot(working));
        expect(prepared['recoveryPath'], isNot(recovery));
        expect(
          await File(working).readAsBytes(),
          documentBytes(1, 'unpublished'),
        );
        expect(
          await File(recovery).readAsBytes(),
          documentBytes(1, 'newest recovery'),
        );
        expect(adapter.publications, 0);
      });
      test('automatic failure log persistence failure is visible and still prevents conversion', () async {
        // Occupy the failure-log path as soon as an attempt is allocated.
        adapter.denyBackup = true;
        await storage.migrations.directory.delete(recursive: true);
        await File(storage.migrations.directory.path)
            .writeAsString('no space/blocked');
        await expectLater(stage(), throwsA(isA<MigrationFailure>()));
        expect(storage.migrations.logFailed, true);
        expect(storage.explanation, contains('could not be saved'));
        expect(preparations, 0);
        expect(adapter.publications, 0);
      });
      if (kind == 'android') {
        test('cancelled folder grant leaves source alone and asks for authorization', () async {
          adapter.cancelFolder = true;
          await expectLater(stage(), throwsA(isA<MigrationFailure>()));
          expect(storage.migrations.issue?['failure'], 'backup_required');
          expect(storage.severe, false);
          expect(preparations, 0);
        });
      }
    });
  }
}
