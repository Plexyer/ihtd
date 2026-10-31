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
    'released 0.2.5 files survive upgrade, combined feature edits, disconnect and restart',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp(
        'ihtd-upgrade-acceptance-',
      );
      final roles = jsonDecode(
        await File('test/fixtures/upgrade-0.2.5/roles.json').readAsString(),
      ) as Map;
      final passport = roles['passport'] as int, trip = roles['trip'] as int;
      final travel = roles['travel_tag'] as int,
          urgent = roles['urgent_tag'] as int;
      Future<String> command(String request) => api.command(request: request);
      for (final name in ['intact', 'customized', 'deleted-default']) {
        final support = Directory('${root.path}/$name-support');
        AppController start() => AppController(
          command: command,
          polling: false,
          supportDirectory: () async => support,
          documentServices: DocumentSaveCoordinator(
            adapter: FilesystemDocumentAdapter(command),
            supportDirectory: () async => support,
          ),
        );
        var app = start();
        await app.ready;
        final original = await File('test/fixtures/upgrade-0.2.5/$name.sqlite')
            .readAsBytes();
        final expected = Map<String, dynamic>.from(
          jsonDecode(
            await File('test/fixtures/upgrade-0.2.5/$name.json').readAsString(),
          ) as Map,
        );
        final source = File('${root.path}/$name.ihtd');
        await source.writeAsBytes(original);
        expect(
          await app.dispatch({'op': 'open', 'path': source.path}),
          isNotNull,
          reason: app.error,
        );
        final protected = app.allTasksViewId!;
        final projected = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(app.document)) as Map,
        );
        final jobs = await app.documentServices.migrations.recoveryAttempts();
        if (name == 'intact') {
          expect(protected, 1);
          expect(jobs, isEmpty);
          expect(await source.readAsBytes(), original);
        } else {
          expect(jobs.length, 1);
          expect(jobs.single['status'], 'completed');
          expect(
            await File(
              jobs.single['backups'][0]['reference']['locator'] as String,
            ).readAsBytes(),
            original,
          );
          expect(protected, expected['next_id']);
          projected.remove('all_tasks_view_id');
          (projected['views'] as Map).remove('$protected');
          projected['next_id'] = (projected['next_id'] as int) - 1;
          projected['revision'] = (projected['revision'] as int) - 1;
        }
        expect(
          projected,
          expected,
          reason: 'Preserve every old item, note, date, completion, tag, link, order, view and preference.',
        );
        expect(app.appearances['$passport'], '2');
        expect(app.issuesForView(roles['broken_view'] as int), isNotEmpty);
        final bytesBeforeQueries = await source.readAsBytes();
        await app.rankedTags(app.editIdentity);
        await app.refreshRows();
        expect(await source.readAsBytes(), bytesBeforeQueries);
        expect(app.document!.containsKey('tag_usage'), false);

        await app.selectItem(passport);
        app.changeItemDraft('notes', 'Accepted after upgrading from $name');
        app.changeItemDraft('tag_ids', [travel, urgent]);
        expect(await app.saveItemDraft(), true, reason: app.error);
        final usage = app.document!['tag_usage'] as Map;
        expect(
          usage.containsKey('$travel'),
          false,
          reason: 'Existing assignments never become new manual usage.',
        );
        expect((usage['$urgent'] as Map).values.toList(), [1]);
        final history = jsonEncode(usage);
        expect(
          await app.dispatch({
            'op': 'set_collection_settings',
            'expected_settings': jsonDecode(jsonEncode(app.collectionSettings)),
            'settings': {
              ...app.collectionSettings,
              'tag_suggestion_count': 3,
              'tag_half_life_days': 7,
            },
          }),
          isNotNull,
          reason: app.error,
        );
        expect(
          await app.dispatch({
            'op': 'set_sort',
            'view_id': protected,
            'parent': null,
            'expected_sort': {'mode': 'manual', 'descending': false},
            'sort': {'mode': 'title', 'descending': false},
          }),
          isNotNull,
          reason: app.error,
        );
        final copy = await app.dispatch({
          'op': 'link_or_copy',
          'source': trip,
          'destination': null,
          'mode': 'copy',
          'depth': null,
          'independent': false,
          'expected_revision': app.document!['revision'],
        });
        expect(copy, isNotNull, reason: app.error);
        expect(app.document!['items']['${copy!['id']}']['title'], 'Japan trip');
        expect(app.appearances['$passport'], '2');
        expect(jsonEncode(app.document!['tag_usage']), history);

        final published = await source.readAsBytes();
        final renamed = await source.rename('${root.path}/$name-renamed.ihtd');
        await app.poll();
        expect(app.documentServices.connection, DocumentConnection.unavailable);
        expect(app.documentServices.severe, false);
        await app.selectItem(passport);
        app.changeItemDraft('notes', 'Locally accepted while unavailable');
        expect(await app.saveItemDraft(), true, reason: app.error);
        expect(app.documentServices.pending, true);
        expect(await renamed.readAsBytes(), published);
        expect(await source.exists(), false);
        await app.selectItem(passport);
        app.changeItemDraft('notes', 'Unfinished private upgrade draft');
        app.chooseDraftExit = (_, _) async => DraftExitChoice.keepEditing;
        expect(await app.prepareForUpdate(), false);
        await app.itemDrafts.flush();
        final savedDocument = jsonDecode(jsonEncode(app.document));
        app.dispose();
        await app.itemDrafts.flush();
        await app.documentServices.diagnostics.flush();
        app = start();
        await app.ready;
        expect(app.document, savedDocument, reason: app.error);
        expect(app.documentServices.pending, true);
        expect(app.recoveredDrafts.length, 1);
        expect(
          await app.restoreItemDraft(app.recoveredDrafts.single),
          true,
          reason: app.error,
        );
        expect(
          app.itemDraft!.values['notes'],
          'Unfinished private upgrade draft',
        );
        expect(await renamed.readAsBytes(), published);
        expect(await app.discardItemDraft(), true);
        final selected = {
          'reference': app.documentServices.adapter
              .referenceFor(renamed.path)
              .toJson(),
        };
        final observed = await app.documentServices.inspect(selected);
        expect(
          await app.documentServices.confirm(
            selected: {...selected, ...observed, 'explicitSelection': true},
          ),
          true,
        );
        expect(app.documentServices.pending, false);
        await app.selectItem(passport);
        app.changeItemDraft('notes', 'Prepared safely before OS update');
        app.chooseDraftExit = (_, _) async => DraftExitChoice.save;
        expect(await app.prepareForUpdate(), true, reason: app.error);
        expect(app.itemDraft?.dirty, false);
        expect(
          app.document!['items']['$passport']['notes'],
          'Prepared safely before OS update',
        );
        final finalDocument = jsonDecode(jsonEncode(app.document));
        app.dispose();
        await app.itemDrafts.flush();
        await app.documentServices.diagnostics.flush();
        app = start();
        await app.ready;
        expect(app.document, finalDocument, reason: app.error);
        expect(
          app.document!['items']['$passport']['notes'],
          'Prepared safely before OS update',
        );
        expect(app.collectionSettings['tag_half_life_days'], 7);
        expect(jsonEncode(app.document!['tag_usage']), history);
        expect(app.recoveredDrafts, isEmpty);
        expect(app.documentServices.pending, false);
        app.dispose();
        await app.itemDrafts.flush();
        await app.documentServices.diagnostics.flush();
      }
      await root.delete(recursive: true);
    },
  );
}
