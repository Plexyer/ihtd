import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:app/ui/item_drag.dart';
import 'package:app/ui/sort_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real insertion gestures preserve hidden slots, per-view choices and save barriers across restart',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp('ihtd-sort-native-');
      final support = Directory('${root.path}/support');
      Future<String> command(String input) => api.command(request: input);
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
      final file = File('${root.path}/Sort.ihtd');
      await app.dispatch({'op': 'new', 'path': file.path});
      Future<int> add(String title, {int? parent, int priority = 0}) async {
        final result = await app.dispatch({
          'op': 'add_item',
          'kind': 'task',
          'title': title,
          'view_id': 1,
          'parent_id': parent,
          'priority': priority,
        });
        expect(result, isNotNull, reason: app.error);
        return result!['id'] as int;
      }

      Future<void> idle() async {
        for (var i = 0; i < 250 && (app.busy || app.savingItemDraft); i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(app.busy, false, reason: app.error);
      }

      final h = await add('Hidden'),
          z = await add('Zulu', priority: 1),
          middle = await add('Hidden middle'),
          b = await add('Beta', priority: 1),
          a = await add('Alpha', priority: 1);
      final manualView =
          (await app.dispatch({
                'op': 'add_view',
                'name': 'Manual elsewhere',
                'filter': {'op': 'all'},
              }))!['id']
              as int;
      final autoView =
          (await app.dispatch({
                'op': 'add_view',
                'name': 'Automatic elsewhere',
                'filter': {'op': 'all'},
              }))!['id']
              as int;
      await app.dispatch({
        'op': 'set_sort',
        'view_id': autoView,
        'parent': null,
        'expected_sort': {'mode': 'manual', 'descending': false},
        'sort': {'mode': 'title', 'descending': true},
      });
      final filteredView =
          (await app.dispatch({
                'op': 'add_view',
                'name': 'Priority filter',
                'filter': {'op': 'priority', 'comparison': 'ge', 'value': 1},
              }))!['id']
              as int;
      await app.selectView(filteredView);
      final beforeItems = jsonDecode(jsonEncode(app.document!['items']));
      final oldRoot = List.from(app.document!['root_order'] as List);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, _) => Column(
                children: [
                  SortControl(app: app),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < app.rows.length; i++)
                          PlacementRow(
                            app: app,
                            row: app.rows[i],
                            endPaths: i == app.rows.length - 1
                                ? const ['']
                                : const [],
                            child: SizedBox(
                              height: 54,
                              width: double.infinity,
                              child: Text(
                                '${app.document!['items']['${app.rows[i]['id']}']['title']}',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sort: Manual'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alphabetic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save sorting'));
      await idle();
      expect(app.rows.map((r) => r['id']).toList(), [a, b, z]);
      expect(
        app.document!['root_order'],
        oldRoot,
        reason: 'automatic sorting does not rewrite manual order',
      );
      Future<void> drag(String from, String to) async {
        final revision = app.document!['revision'];
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey(from))),
        );
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(to))));
        await tester.pump();
        await gesture.up();
        for (var i = 0; i < 250 && app.document!['revision'] == revision; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await idle();
        expect(app.error, isNull);
        expect(app.document!['revision'], (revision as int) + 1);
      }

      await drag('drag-$z', 'before-$b');
      expect(app.document!['root_order'], [h, a, middle, z, b]);
      expect(sortFor(app, filteredView, null)['mode'], 'manual');
      expect(sortFor(app, autoView, null), {
        'mode': 'title',
        'descending': true,
      });
      await drag('drag-$z', 'after-root');
      expect(app.document!['root_order'], [h, a, middle, b, z]);
      expect(app.document!['items'], beforeItems);
      await app.selectView(manualView);
      expect(app.rows.map((r) => r['id']).toList(), [h, a, middle, b, z]);
      // Moving out of a parent with inherited appearances is blocked without mutation.
      await app.selectView(1);
      final p = await add('Parent A'),
          q = await add('Parent B'),
          f = await add('Shared folder', parent: p),
          child = await add('Child', parent: f);
      await app.dispatch({
        'op': 'link_or_copy',
        'source': f,
        'destination': q,
        'mode': 'link',
        'depth': 0,
        'independent': false,
        'expected_revision': app.document!['revision'],
      });
      final unchanged = jsonDecode(jsonEncode(app.document));
      expect(
        await app.moveOccurrence(
          owner: app.editIdentity,
          view: 1,
          completed: false,
          sourcePath: '$p/$f/$child',
          destinationPath: '',
          reorder: false,
        ),
        false,
      );
      expect(app.error, contains('independent copy'));
      expect(app.document, unchanged);
      final preserved = await file.readAsBytes();
      await file.rename('${root.path}/Renamed.ihtd');
      await app.poll();
      await app.dispatch({
        'op': 'set_sort',
        'view_id': 1,
        'parent': null,
        'expected_sort': {'mode': 'manual', 'descending': false},
        'sort': {'mode': 'priority', 'descending': true},
      }, expectedDocument: app.editIdentity);
      expect(app.documentServices.pending, true);
      expect(await file.exists(), false);
      final finalDoc = jsonDecode(jsonEncode(app.document));
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.document, finalDoc);
      expect(app.documentServices.pending, true);
      expect(sortFor(app, 1, null), {'mode': 'priority', 'descending': true});
      expect(await File('${root.path}/Renamed.ihtd').readAsBytes(), preserved);
      app.dispose();
      await app.documentServices.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
