import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/services/document_adapter.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/migration_contract.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAdapter implements DocumentAdapter {
  FakeAdapter(this.kind);
  @override
  final String kind;
  @override
  List<String> get legacyRegistryNames =>
      kind == 'android' ? ['android-documents'] : [];
  String contents = 'baseline', name = 'Tasks.ihtd', identity = 'file-one';
  bool available = true;
  int writes = 0;
  DocumentFailureKind? failure;
  @override
  DocumentReference referenceFor(String locator) =>
      DocumentReference(kind, locator);
  @override
  Future<Map<String, dynamic>> environment() async => {'appVersion': '0.2.2'};
  @override
  Future<DocumentReference?> pick({String? suggested}) async => null;
  @override
  Future<String> localHash(String path) => File(path).readAsString();
  @override
  Future<DocumentRead> read(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async => DocumentRead(Uint8List.fromList(utf8.encode(contents)), contents);
  @override
  Future<DocumentObservation> inspect(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async {
    if (!available) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    return DocumentObservation(hash: contents, name: name, identity: identity);
  }

  @override
  Future<DocumentObservation> publish(
    DocumentReference reference,
    String workingPath, {
    required String expectedHash,
    String? expectedName,
    String? expectedIdentity,
    bool create = false,
  }) async {
    writes++;
    if (failure != null) throw DocumentFailure(failure!);
    if (!available) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    if (expectedIdentity != null && expectedIdentity != identity) {
      throw const DocumentFailure(DocumentFailureKind.replaced);
    }
    if (contents != expectedHash) {
      throw const DocumentFailure(DocumentFailureKind.externalChanged);
    }
    contents = await localHash(workingPath);
    identity = 'saved-$writes'; // Atomic filesystem publication changes the ID.
    return inspect(reference);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['android', 'filesystem']) {
    group('$kind common save contract', () {
      late Directory support;
      late DocumentSaveCoordinator coordinator;
      late FakeAdapter adapter;
      late String working;
      setUp(() async {
        support = await Directory.systemTemp.createTemp('ihtd-contract-');
        adapter = FakeAdapter(kind);
        coordinator = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => support,
        );
        await coordinator.initialize();
        working = coordinator.freshPath();
        await File(working).writeAsString(adapter.contents);
        await coordinator.attach({
          'reference': adapter.referenceFor('selected').toJson(),
          'path': working,
          'name': adapter.name,
          'hash': adapter.contents,
          'identity': adapter.identity,
        });
      });
      tearDown(() async {
        await coordinator.diagnostics.flush();
        await support.delete(recursive: true);
      });

      test('rename + pending edits require explicit confirmation', () async {
        adapter.name = 'Renamed.ihtd';
        await coordinator.check();
        expect(coordinator.connection, DocumentConnection.renamed);
        await File(working).writeAsString('edit');
        await coordinator.publish();
        expect(coordinator.pending, true);
        expect(adapter.writes, 0);
        expect(await coordinator.confirm(), true);
        expect(adapter.contents, 'edit');
        await coordinator.check();
        expect(coordinator.connection, DocumentConnection.connected);
        expect(
          coordinator.pending,
          false,
        ); // New confirmed identity is retained.
      });
      test(
        'external content and same-name replacement never overwrite',
        () async {
          adapter.contents = 'external';
          await File(working).writeAsString('edit');
          await coordinator.publish();
          expect(await coordinator.confirm(), false);
          expect(adapter.writes, 0);
          adapter.contents = 'baseline';
          adapter.identity = 'replacement';
          await coordinator.check();
          expect(coordinator.connection, DocumentConnection.replaced);
          expect(await coordinator.confirm(), false);
          expect(adapter.writes, 0);
        },
      );
      test(
        'lost access is yellow and restoration does not release the barrier',
        () async {
          adapter.available = false;
          await coordinator.check();
          await File(working).writeAsString('edit');
          await coordinator.publish();
          expect(coordinator.severe, false);
          expect(adapter.writes, 0);
          adapter.available = true;
          await coordinator.publish();
          expect(coordinator.connection, DocumentConnection.reconnectRequired);
          expect(adapter.writes, 0);
          expect(await coordinator.confirm(), true);
        },
      );
      test('replacement needs explicit selection, exact baseline and fresh approval', () async {
        adapter.identity = 'replacement';
        await File(working).writeAsString('edit');
        await coordinator.check();
        expect(await coordinator.confirm(), false);
        final selected = {
          ...coordinator.binding!,
          ...(await coordinator.inspect(coordinator.binding!)),
          'explicitSelection': true,
        };
        expect(await coordinator.confirm(selected: selected), true);
        expect(adapter.contents, 'edit');
      });
      for (final failure in [
        DocumentFailureKind.writeFailed,
        DocumentFailureKind.verificationFailed,
      ]) {
        test('$failure is red with no automatic retry', () async {
          adapter.failure = failure;
          await File(working).writeAsString('edit');
          await coordinator.publish();
          await coordinator.publish();
          expect(coordinator.severe, true);
          expect(adapter.writes, 1);
          adapter.failure = null;
          expect(await coordinator.confirm(), true);
        });
      }
      test(
        'restoring a retained write failure preserves its red barrier',
        () async {
          adapter.failure = DocumentFailureKind.writeFailed;
          await File(working).writeAsString('edit');
          await coordinator.publish();
          await coordinator.archive();
          final record = Map<String, dynamic>.from(
            jsonDecode(await File('$working.binding.json').readAsString()),
          );
          final restored = DocumentSaveCoordinator(
            adapter: adapter,
            supportDirectory: () async => support,
          );
          await restored.initialize();
          await restored.attach(record, retained: true);
          await restored.publish();
          expect(restored.severe, true);
          expect(adapter.writes, 1);
          await restored.diagnostics.flush();
        },
      );
      test('restart retains pending work and confirmation barrier', () async {
        await File(working).writeAsString('edit');
        final restored = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => support,
        );
        await restored.initialize();
        await restored.publish();
        expect(restored.pending, true);
        expect(adapter.writes, 0);
        expect(restored.connection, DocumentConnection.reconnectRequired);
        await restored.diagnostics.flush();
      });
      test(
        'stale approval and partial writes do not overwrite external data',
        () async {
          await File(working).writeAsString('edit');
          expect(
            await coordinator.confirm(
              selected: {
                ...coordinator.binding!,
                'name': 'stale',
                'hash': 'baseline',
              },
            ),
            false,
          );
          adapter.failure = DocumentFailureKind.verificationFailed;
          await coordinator.publish();
          adapter.contents = 'partial';
          expect(await coordinator.confirm(), false);
          expect(adapter.contents, 'partial');
          expect(adapter.writes, 1);
        },
      );
      test('archive and diagnostic redaction use the same policy', () async {
        await File(working).writeAsString('PRIVATE NOTES');
        await coordinator.check();
        await coordinator.archive();
        final output = coordinator.diagnostics.export(
          state: 'connected',
          pending: true,
        );
        for (final text in [
          'PRIVATE NOTES',
          'Tasks.ihtd',
          working,
          'selected',
          adapter.identity,
        ]) {
          expect(output, isNot(contains(text)));
        }
        expect(await File('$working.binding.json').exists(), true);
      });
    });
  }

  test('interrupted Android metadata migration preserves the legacy source and can retry', () async {
    final support = await Directory.systemTemp.createTemp(
      'ihtd-migration-failure-',
    );
    final legacy = Directory('${support.path}/android-documents');
    await legacy.create();
    final old = File('${legacy.path}/active.json');
    final original = jsonEncode({
      'version': 2,
      'uri': 'selected',
      'path': '${legacy.path}/working.ihtd',
      'name': 'Tasks.ihtd',
      'hash': 'baseline',
      'pending': true,
      'barrier': 'renamed',
    });
    await old.writeAsString(original);
    final blocker = Directory('${support.path}/documents/active.json.tmp');
    await blocker.create(recursive: true);
    final coordinator = DocumentSaveCoordinator(
      adapter: FakeAdapter('android'),
      supportDirectory: () async => support,
    );
    await expectLater(
      coordinator.initialize(),
      throwsA(isA<MigrationFailure>()),
    );
    expect(await old.readAsString(), original);
    expect(
      await coordinator.migrations.exportLog(),
      contains('metadata_failed'),
    );
    final backups = await legacy
        .list()
        .where((file) => file.path.contains('before-upgrade'))
        .toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsString(), original);
    expect(await File('${support.path}/documents/active.json').exists(), false);
    await blocker.delete();
    await coordinator.initialize();
    expect(coordinator.connection, DocumentConnection.renamed);
    expect(coordinator.pending, true);
    expect(await old.readAsString(), original);
    await coordinator.diagnostics.flush();
    await support.delete(recursive: true);
  });

  test('legacy Android migration is atomic, preserves pending barriers and old recovery paths', () async {
    final support = await Directory.systemTemp.createTemp('ihtd-migration-');
    final legacy = Directory('${support.path}/android-documents');
    await legacy.create();
    final working = File('${legacy.path}/working.ihtd');
    await working.writeAsString('pending edits');
    final recovery = File('${support.path}/recovery.ihtd');
    await recovery.writeAsString('retained');
    final active = File('${legacy.path}/active.json');
    await active.writeAsString(
      jsonEncode({
        'version': 2,
        'uri': 'selected',
        'name': 'Tasks.ihtd',
        'path': working.path,
        'hash': 'baseline',
        'barrier': 'renamed',
        'pending': true,
        'localDirty': true,
        'recoveryPath': recovery.path,
      }),
    );
    final adapter = FakeAdapter('android');
    final coordinator = DocumentSaveCoordinator(
      adapter: adapter,
      supportDirectory: () async => support,
    );
    await coordinator.initialize();
    await coordinator.publish();
    expect(coordinator.binding!['version'], 3);
    expect(coordinator.binding!['reference']['kind'], 'android');
    expect(coordinator.localDirty, true);
    expect(coordinator.pending, true);
    expect(adapter.writes, 0);
    expect(await active.exists(), true);
    expect(await recovery.readAsString(), 'retained');
    await coordinator.diagnostics.flush();
    await support.delete(recursive: true);
  });
  for (final type in ['future', 'corrupt']) {
    test(
      '$type registry is preserved and cannot be silently downgraded by a background check',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'ihtd-registry-guard-',
        );
        final docs = Directory('${support.path}/documents');
        await docs.create();
        final active = File('${docs.path}/active.json');
        final original = type == 'future'
            ? jsonEncode({
                'version': 4,
                'reference': {
                  'kind': 'android',
                  'locator': 'private-future-uri',
                },
                'path': 'private-future-working',
                'pending': true,
              })
            : '{incomplete private metadata';
        await active.writeAsString(original);
        final adapter = FakeAdapter('android');
        final coordinator = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => support,
        );
        await expectLater(
          coordinator.initialize(),
          throwsA(isA<MigrationFailure>()),
        );
        expect(coordinator.binding, isNull);
        await coordinator.check();
        expect(await active.readAsString(), original);
        final backups = await docs
            .list()
            .where((file) => file.path.contains('before-upgrade'))
            .toList();
        expect(backups, hasLength(1));
        expect(await File(backups.single.path).readAsString(), original);
        final log = await coordinator.migrations.exportLog();
        expect(log, isNot(contains('private-future')));
        expect(log, isNot(contains('incomplete private')));
        expect(adapter.writes, 0);
        await coordinator.diagnostics.flush();
        await support.delete(recursive: true);
      },
    );
  }
}
