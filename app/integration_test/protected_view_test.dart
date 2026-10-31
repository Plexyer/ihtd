import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/services/item_draft.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'protected view upgrade preserves customized views, pending files and private drafts',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp(
        'ihtd-protected-native-',
      );
      Future<String> command(String request) => api.command(request: request);
      Directory support = Directory('${root.path}/normal-support');
      DocumentSaveCoordinator storage() => DocumentSaveCoordinator(
        adapter: FilesystemDocumentAdapter(command),
        supportDirectory: () async => support,
      );
      AppController start(DocumentSaveCoordinator coordinator) => AppController(
        command: command,
        polling: false,
        supportDirectory: () async => support,
        documentServices: coordinator,
      );
      var coordinator = storage();
      var app = start(coordinator);
      await app.ready;
      final unchanged = await File('test/fixtures/migration-schema2.sqlite')
          .readAsBytes();
      final normal = File('${root.path}/Normal.ihtd');
      await normal.writeAsBytes(unchanged);
      expect(
        await app.dispatch({'op': 'open', 'path': normal.path}),
        isNotNull,
        reason: app.error,
      );
      expect(app.allTasksViewId, 1);
      expect(await normal.readAsBytes(), unchanged);
      expect(await coordinator.migrations.recoveryAttempts(), isEmpty);
      app.dispose();
      await app.itemDrafts.flush();
      await coordinator.diagnostics.flush();

      support = Directory('${root.path}/custom-support');
      coordinator = storage();
      app = start(coordinator);
      await app.ready;
      final original = await File(
        'test/fixtures/protected-view-customized.sqlite',
      ).readAsBytes();
      final source = File('${root.path}/Customized.ihtd');
      await source.writeAsBytes(original);
      expect(
        await app.dispatch({'op': 'open', 'path': source.path}),
        isNotNull,
        reason: app.error,
      );
      final protectedId = app.allTasksViewId!;
      expect(protectedId, 9);
      expect(app.selectedViewId, protectedId);
      expect(app.document!['views']['1']['name'], 'My travel');
      expect(app.document!['views']['1']['filter'], {'op': 'tag', 'tag_id': 6});
      expect(app.document!['views']['1']['sorting']['0'], {
        'mode': 'title',
        'descending': true,
      });
      expect(app.document!['tag_usage']['6']['1793404800'], 2);
      expect(app.collectionSettings['tag_half_life_days'], 7);
      expect(app.document!['parent_indicator_defaults']['2']['total'], false);
      expect(app.document!['views']['7']['name'], 'Custom travel');
      final preservedView = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(app.document!['views']['1'])) as Map,
      );
      expect(app.document!['revision'], 43);
      var job = (await coordinator.migrations.recoveryAttempts()).single;
      expect(job['status'], 'completed');
      expect(job['plans'], ['protected-all-tasks']);
      final backups = job['backups'] as List;
      expect(backups.length, 1);
      expect(
        await File(backups.single['reference']['locator'] as String)
            .readAsBytes(),
        original,
      );
      final before = jsonEncode(app.document);
      expect(
        await app.dispatch({'op': 'remove_view', 'id': protectedId}),
        isNull,
      );
      expect(jsonEncode(app.document), before);
      expect(
        await app.dispatch({
          'op': 'edit_view',
          'id': protectedId,
          'name': 'Changed',
          'filter': {'op': 'all'},
        }),
        isNull,
      );
      expect(jsonEncode(app.document), before);
      expect(
        await app.dispatch({
          'op': 'set_sort',
          'view_id': protectedId,
          'parent': null,
          'expected_sort': {'mode': 'manual', 'descending': false},
          'sort': {'mode': 'priority', 'descending': true},
        }),
        isNotNull,
        reason: app.error,
      );
      expect(
        await app.dispatch({
          'op': 'set_preferences',
          'view_id': protectedId,
          'item_id': 2,
          'preferences': {'hide_completed': true},
        }),
        isNotNull,
        reason: app.error,
      );
      await app.selectView(1);
      expect(
        await app.dispatch({
          'op': 'edit_view',
          'id': 1,
          'name': 'Still editable',
          'filter': {'op': 'tag', 'tag_id': 6},
        }),
        isNotNull,
        reason: app.error,
      );
      app.dispose();
      await app.itemDrafts.flush();
      await coordinator.diagnostics.flush();
      coordinator = storage();
      app = start(coordinator);
      await app.ready;
      expect(app.error, isNull);
      expect(app.allTasksViewId, protectedId);
      expect(app.document!['views']['1']['name'], 'Still editable');
      expect((await coordinator.migrations.recoveryAttempts()).length, 1);
      app.dispose();
      await app.itemDrafts.flush();
      await coordinator.diagnostics.flush();

      // Simulate upgrading the previous app with unpublished working/recovery data
      // and a separately checkpointed, unfinished editor draft.
      support = Directory('${root.path}/retained-support');
      coordinator = storage();
      await coordinator.initialize();
      final pending = await File('test/fixtures/protected-view-pending.sqlite')
          .readAsBytes();
      final external = File('${root.path}/Retained.ihtd');
      await external.writeAsBytes(original);
      final working = File('${coordinator.directory.path}/old-working.ihtd');
      await working.writeAsBytes(pending);
      final recovery = File('${coordinator.directory.path}/old-recovery.ihtd');
      await recovery.writeAsBytes(pending);
      await coordinator.remember({
        'reference': coordinator.adapter.referenceFor(external.path).toJson(),
        ...await coordinator.inspect({
          'reference': coordinator.adapter.referenceFor(external.path).toJson(),
        }),
        'path': working.path,
        'recoveryPath': recovery.path,
        'localDirty': true,
        'pending': true,
        'localDurable': true,
        'barrier': 'reconnectRequired',
      });
      final values = {
        'title': 'Unpublished accepted title',
        'notes': 'Synthetic notes 日本',
        'kind': 'task',
        'priority': 3,
        'due_date': '2026-12-01',
        'tag_ids': [6],
        'auto_complete': false,
        'completed': false,
      };
      final draft = ItemDraft(
        ownerPath: working.path,
        documentId: 'synthetic-upgrade-collection',
        viewId: 1,
        view: {
          'id': 1,
          'name': 'My travel',
          'filter': {'op': 'tag', 'tag_id': 6},
        },
        itemId: 4,
        base: {'id': 4, ...values},
        values: Map.from(values),
      );
      draft.values['notes'] = 'Unfinished private note';
      final store = ItemDraftStore();
      await store.initialize(support);
      await store.put(draft);
      final newDraft = ItemDraft(
        ownerPath: working.path,
        documentId: 'synthetic-upgrade-collection',
        viewId: 1,
        view: preservedView,
        base: {},
        values: {...values, 'title': 'Unfinished new task'},
      );
      newDraft.intent = {
        'digest': 'unaccepted-proposal',
        'id': 9,
        'revision': 43,
      };
      await store.put(newDraft);

      final draftFile = File('${store.directory.path}/${draft.sessionId}.json');
      final draftBytes = await draftFile.readAsBytes();
      app = start(coordinator);
      await app.ready;
      expect(app.error, isNull);
      expect(
        app.document!['items']['4']['title'],
        'Unpublished accepted title',
      );
      expect(app.document!['items']['4']['notes'], 'Synthetic notes 日本');
      expect(app.allTasksViewId, 9);
      expect(app.selectedViewId, 9);
      expect(coordinator.pending, true);
      expect(await external.readAsBytes(), original);
      expect(await working.readAsBytes(), pending);
      expect(await recovery.readAsBytes(), pending);
      expect(await draftFile.readAsBytes(), draftBytes);
      job = (await coordinator.migrations.recoveryAttempts()).single;
      expect((job['backups'] as List).length, 3);
      final evidence = (job['candidates'] as List).firstWhere(
        (c) => c['role'] == 'path',
      );
      final committedDraft = ItemDraft.fromJson({
        ...draft.toJson(),
        'session': '${DateTime.now().microsecondsSinceEpoch}-abc',
        'intent': {'digest': evidence['sourceDigest'], 'id': 4, 'revision': 42},
      });
      await store.put(committedDraft);
      final beforeReceipt = jsonEncode(app.document);
      expect(
        await app.restoreItemDraft(committedDraft),
        true,
        reason: app.error,
      );
      expect(jsonEncode(app.document), beforeReceipt);
      expect(app.itemDraft, isNull);
      expect(
        await File('${store.directory.path}/${committedDraft.sessionId}.json')
            .exists(),
        false,
      );
      expect(app.error, contains('already saved'));

      for (final backup in job['backups'] as List) {
        expect(
          await File(backup['reference']['locator'] as String).readAsBytes(),
          backup['role'] == 'external' ? original : pending,
        );
      }
      expect(
        await app.restoreItemDraft(
          app.recoveredDrafts.singleWhere((d) => !d.isNew),
        ),
        true,
        reason: app.error,
      );
      expect(app.itemDraft!.ownerPath, app.editIdentity.workingPath);
      expect(app.itemDraft!.values['notes'], 'Unfinished private note');
      expect(
        await draftFile.readAsBytes(),
        draftBytes,
        reason: 'Restore never auto-saves or rewrites draft fields',
      );
      expect(await app.saveItemDraft(), true, reason: app.error);
      expect(app.document!['items']['4']['notes'], 'Unfinished private note');
      expect(
        coordinator.pending,
        true,
        reason: 'Restored edits still require destination confirmation',
      );
      expect(await external.readAsBytes(), original);
      final beforeCreation = app.document!['next_id'];
      expect(
        await app.restoreItemDraft(
          app.recoveredDrafts.singleWhere((d) => d.isNew),
        ),
        true,
        reason: app.error,
      );
      expect(
        app.document!['next_id'],
        beforeCreation,
        reason: 'Restore must not create an item',
      );
      expect(await app.saveItemDraft(), true, reason: app.error);
      expect(
        app.document!['items']['$beforeCreation']['title'],
        'Unfinished new task',
      );
      expect(app.document!['items']['$beforeCreation']['tag_ids'], [6]);
      expect(await external.readAsBytes(), original);
      app.dispose();
      await app.itemDrafts.flush();
      await coordinator.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
