import 'dart:convert';
import 'dart:io';

import 'package:app/services/android_documents.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/app_controller.dart';
import 'package:app/ui/document_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DocumentSaveCoordinator storage;
  late AppController app;
  late String workingPath;
  String remote = 'original', filename = 'Tasks.ihtd';
  int writes = 0, revision = 0;
  bool localFailure = false;
  Map<String, dynamic>? picker;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, dynamic> snapshot() => {
    'path': workingPath,
    'dirty': false,
    'recovery_path': '$workingPath.recovery',
    'document': {
      'document_id': 'copied-id',
      'revision': revision,
      'views': {'1': {}},
      'items': {
        '1': {'title': 'Private title'},
      },
    },
    'completion': {},
  };
  Future<String> command(String request) async {
    final operation = jsonDecode(request) as Map;
    if (operation['op'] == 'update_item' && localFailure) {
      return jsonEncode({
        'ok': false,
        'error': 'Private recovery write failed',
        'snapshot': {...snapshot(), 'persistence_failed': true},
        'data': {},
      });
    }
    if (operation['op'] == 'update_item') {
      revision++;
      await File(workingPath).writeAsString('edited-$revision');
    }
    if (operation['op'] == 'open' && operation['path'] != null) {
      workingPath = operation['path'] as String;
    }
    return jsonEncode({
      'ok': true,
      'snapshot': snapshot(),
      'data': {'rows': [], 'reloaded': false},
    });
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ihtd-controller-');
    remote = 'original';
    filename = 'Tasks.ihtd';
    writes = 0;
    revision = 0;
    picker = null;
    localFailure = false;
    messenger.setMockMethodCallHandler(AndroidDocumentAdapter.channel, (
      call,
    ) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      switch (call.method) {
        case 'environment':
          return {'appVersion': '0.2.2'};
        case 'localHash':
          return File(args['path'] as String).readAsString();
        case 'inspect':
          return {'name': filename, 'hash': remote};
        case 'read':
          return {
            'bytes': Uint8List.fromList(utf8.encode(remote)),
            'hash': remote,
          };
        case 'write':
          writes++;
          remote = await File(args['path'] as String).readAsString();
          return remote;
        case 'open':
          return picker;
        case 'create':
          return null;
        default:
          throw StateError('Unexpected ${call.method}');
      }
    });
    storage = DocumentSaveCoordinator(
      adapter: AndroidDocumentAdapter(),
      supportDirectory: () async => directory,
    );
    await storage.initialize();
    workingPath = storage.freshPath();
    await File(workingPath).writeAsString(remote);
    await storage.attach({
      'uri': 'content://test/1',
      'path': workingPath,
      'name': filename,
      'hash': remote,
    });
    app = AppController(
      documentServices: storage,
      command: command,
      supportDirectory: () async => directory,
      polling: false,
    );
    await app.ready;
  });
  tearDown(() async {
    app.dispose();
    await storage.diagnostics.flush();
    messenger.setMockMethodCallHandler(AndroidDocumentAdapter.channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'resume detection, mutation and opening task preserve blocked save status',
    () async {
      filename = 'Renamed.ihtd';
      await app.poll();
      expect(app.status, 'Filename changed — confirmation needed');
      await app.dispatch({'op': 'update_item'});
      expect(app.status, 'Pending changes — not saved to file');
      await app.selectItem(1);
      await app.selectView(1);
      await app.poll();
      app.clearError();
      expect(writes, 0);
      expect(remote, 'original');
      expect(storage.connection, DocumentConnection.renamed);
      expect(app.status, 'Pending changes — not saved to file');
      app.confirmDocumentAction = (_, _) async => true;
      await app.reconnectDocument();
      expect(remote, 'edited-1');
      expect(app.status, 'Saved to file');
      expect(app.documentName, filename);
    },
  );
  test('cancelled confirmation and cancelled picker preserve active session and pending work', () async {
    filename = 'Renamed.ihtd';
    await app.dispatch({'op': 'update_item'});
    app.confirmDocumentAction = (_, _) async => false;
    await app.reconnectDocument();
    await app.openDocument();
    expect(writes, 0);
    app.confirmDocumentAction = (_, _) async => true;
    final original = app.path;
    await app.openDocument();
    expect(app.path, original);
    expect(storage.pending, true);
    expect(writes, 0);
  });
  test('switching to external version retains previous edits, never applies them to opened file', () async {
    filename = 'Renamed.ihtd';
    await app.dispatch({'op': 'update_item'});
    remote = 'externally-changed';
    picker = {'uri': 'content://test/2', 'name': filename};
    app.confirmDocumentAction = (_, _) async => true;
    await app.openDocument();
    expect(writes, 0);
    expect(remote, 'externally-changed');
    final retained = await storage.retainedCollections();
    expect(retained.single['reference']['locator'], 'content://test/1');
    expect(
      await File(retained.single['path'] as String).readAsString(),
      'edited-1',
    );
    await app.restoreRetained(retained.single);
    expect(storage.pending, true);
    expect(writes, 0);
  });
  test('a failed private recovery write is red without falsely claiming durable edits', () async {
    localFailure = true;
    expect(await app.dispatch({'op': 'update_item'}), null);
    expect(storage.severe, true);
    expect(storage.localDurable, false);
    expect(app.status, contains('Local saving failed'));
    expect(remote, 'original');
    expect(writes, 0);
  });

  testWidgets(
    'warning popup and advanced export cancellation never publish edits',
    (tester) async {
      await tester.runAsync(() async {
        filename = 'Renamed.ihtd';
        await app.dispatch({'op': 'update_item'});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocumentStatus(app: app)),
        ),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await tester.tap(find.text('Pending changes — not saved to file'));
      await tester.pumpAndSettle();
      expect(find.text('File connection and saving'), findsOneWidget);
      expect(find.textContaining('Filename changed from'), findsOneWidget);
      expect(writes, 0);
      await tester.ensureVisible(find.text('Advanced details'));
      await tester.tap(find.text('Advanced details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Include additional file information'),
      );
      await tester.tap(find.text('Include additional file information'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export diagnostic log…'));
      await tester.tap(find.text('Export diagnostic log…'));
      await tester.pumpAndSettle();
      expect(find.text('Include additional information?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(storage.pending, true);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(storage.connection, DocumentConnection.renamed);
      expect(writes, 0);
    },
  );
}
