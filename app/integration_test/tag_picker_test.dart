import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:app/ui/tag_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'tag choices and real manual popularity preserve old files, cancellations, copies and pending recovery',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp('ihtd-tag-native-');
      final support = Directory('${root.path}/support');
      var now = DateTime.utc(2026, 10, 31, 12);
      Future<String> command(String request) => api.command(request: request);
      AppController start() => AppController(
        command: command,
        polling: false,
        now: () => now,
        supportDirectory: () async => support,
        documentServices: DocumentSaveCoordinator(
          adapter: FilesystemDocumentAdapter(command),
          supportDirectory: () async => support,
        ),
      );
      var app = start();
      await app.ready;
      final source = File('${root.path}/Original.ihtd');
      final fixture = await File('test/fixtures/migration-schema2.sqlite')
          .readAsBytes();
      await source.writeAsBytes(fixture);
      expect(
        await app.dispatch({'op': 'open', 'path': source.path}),
        isNotNull,
        reason: app.error,
      );
      final revision = app.document!['revision'];
      final workingBytes = await File(app.editIdentity.workingPath!)
          .readAsBytes();
      expect(await app.rankedTags(app.editIdentity), [6]);
      expect(app.document!.containsKey('tag_usage'), false);
      expect(app.document!['revision'], revision);
      expect(await source.readAsBytes(), fixture);
      expect(
        await File(app.editIdentity.workingPath!).readAsBytes(),
        workingBytes,
      );
      Future<int> addTag(String name) async =>
          (await app.dispatch({'op': 'add_tag', 'name': name}))!['id'] as int;
      final alpha = await addTag('Alpha'), zulu = await addTag('Zulu');
      expect(await app.rankedTags(app.editIdentity), [alpha, 6, zulu]);
      await app.selectView(7);
      final defaults = (await app.dispatch({
        'op': 'creation_defaults',
        'view_id': 7,
      }))!;
      expect(
        await app.beginCreateDraft({
          ...defaults,
          'title': 'Automatic tag task',
        }),
        true,
      );
      expect(await app.saveItemDraft(), true, reason: app.error);
      final automatic = (app.document!['next_id'] as int) - 1;
      expect(app.document!.containsKey('tag_usage'), false);
      await app.selectView(1);
      await app.selectItem(4);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, _) => app.itemDraft == null
                  ? const SizedBox.shrink()
                  : TagSelector(
                      app: app,
                      sessionId: app.itemDraft!.sessionId,
                      selected: List<int>.from(
                        app.itemDraft!.values['tag_ids'] as List,
                      ),
                      disabled: app.busy,
                    ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();
      }

      await settle();
      Future<void> chooseAlpha(String action) async {
        await tester.tap(find.text('Select other…'));
        await settle();
        final search = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Search tags',
        );
        await tester.enterText(search, 'alpha');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pick-tag-$alpha')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await settle();
      }

      await chooseAlpha('Cancel');
      expect(app.itemDraft!.values['tag_ids'], [6]);
      await chooseAlpha('Done');
      expect(app.itemDraft!.values['tag_ids'], [6, alpha]);
      expect(app.document!.containsKey('tag_usage'), false);
      expect(await app.saveItemDraft(), true, reason: app.error);
      await tester.pumpWidget(const SizedBox.shrink());
      String timeKey() => '${now.millisecondsSinceEpoch ~/ 1000}';
      expect(app.document!['tag_usage']['$alpha'][timeKey()], 1);
      expect((app.document!['tag_usage'] as Map).containsKey('6'), false);
      final history = jsonEncode(app.document!['tag_usage']);
      expect(
        await app.dispatch({
          'op': 'link_or_copy',
          'source': 4,
          'destination': null,
          'mode': 'copy',
          'depth': null,
          'independent': false,
          'expected_revision': app.document!['revision'],
        }),
        isNotNull,
        reason: app.error,
      );
      expect(jsonEncode(app.document!['tag_usage']), history);
      now = now.add(const Duration(days: 3));
      await app.selectItem(automatic);
      app.changeItemDraft('tag_ids', [6, zulu]);
      expect(await app.saveItemDraft(), true, reason: app.error);
      expect((await app.rankedTags(app.editIdentity))!.first, zulu);
      final oldSettings = jsonDecode(
        jsonEncode(app.collectionSettings),
      ) as Map<String, dynamic>;
      expect(
        await app.dispatch({
          'op': 'set_collection_settings',
          'expected_settings': oldSettings,
          'settings': {
            ...oldSettings,
            'tag_suggestion_count': 1,
            'tag_half_life_days': 7,
          },
        }),
        isNotNull,
      );
      final published = await source.readAsBytes();
      final renamed = await source.rename('${root.path}/Renamed.ihtd');
      await app.selectItem(4);
      app.changeItemDraft('tag_ids', [6, alpha, zulu]);
      app.changeItemDraft('title', '');
      expect(await app.saveItemDraft(), false);
      expect(app.document!['tag_usage']['$zulu'][timeKey()], 1);
      app.changeItemDraft('title', 'Pack passport');
      expect(await app.saveItemDraft(), true, reason: app.error);
      expect(app.documentServices.pending, true);
      expect(app.document!['tag_usage']['$zulu'][timeKey()], 2);
      expect(await renamed.readAsBytes(), published);
      await app.selectItem(4);
      app.changeItemDraft('notes', 'Unfinished draft');
      await app.checkpointItemDraft();
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.documentServices.pending, true);
      expect(app.document!['tag_usage']['$zulu'][timeKey()], 2);
      expect(app.collectionSettings['tag_suggestion_count'], 1);
      expect(app.collectionSettings['tag_half_life_days'], 7);
      expect(app.recoveredDrafts, isNotEmpty);
      expect((await app.rankedTags(app.editIdentity))!.first, zulu);
      expect(await source.exists(), false);
      expect(await renamed.readAsBytes(), published);
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
