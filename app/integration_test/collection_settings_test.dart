import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'collection and inherited settings preserve distributed data, drafts and file barriers across restart',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp(
        'ihtd-native-settings-',
      );
      final support = Directory('${root.path}/support');
      Future<String> command(String request) => api.command(request: request);
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
      final original = File('${root.path}/Original.ihtd');
      final source = await File('test/fixtures/migration-schema2.sqlite')
          .readAsBytes();
      await original.writeAsBytes(source);
      await app.dispatch({'op': 'open', 'path': original.path});
      expect(app.error, isNull);
      expect(
        await original.readAsBytes(),
        source,
        reason: 'default settings do not rewrite old collections on open',
      );
      final before = jsonDecode(jsonEncode(app.document)) as Map;
      expect(app.collectionSettings['tag_suggestion_count'], 5);
      expect(app.collectionSettings['tag_half_life_days'], 3);
      await app.selectItem(4);
      app.changeItemDraft('notes', 'Unfinished item edit');
      await app.itemDrafts.flush();
      final settings = Map<String, dynamic>.from(app.collectionSettings);
      final saved = await app.dispatch({
        'op': 'set_collection_settings',
        'expected_settings': settings,
        'settings': {
          ...settings,
          'tag_suggestion_count': 8,
          'tag_half_life_days': 7,
        },
      }, expectedDocument: app.editIdentity);
      expect(saved, isNotNull);
      expect(app.itemDraft!.values['notes'], 'Unfinished item edit');
      expect(
        app.document!['items']['4']['notes'],
        before['items']['4']['notes'],
      );
      expect(
        await app.dispatch({
          'op': 'set_indicator_settings',
          'item_id': 4,
          'view_id': 1,
          'expected_parent': {},
          'expected_view': {},
          'parent_overrides': {'next_due_date': true},
          'view_overrides': {'total': false},
        }, expectedDocument: app.editIdentity),
        isNotNull,
      );
      expect(app.document!['items'], before['items']);
      expect(app.document!['tags'], before['tags']);
      expect(app.document!['links'], before['links']);
      expect(app.document!['root_order'], before['root_order']);
      final persisted = await original.readAsBytes();
      await app.discardItemDraft();
      final renamed = File('${root.path}/Renamed.ihtd');
      await original.rename(renamed.path);
      await app.poll();
      final second = Map<String, dynamic>.from(app.collectionSettings);
      expect(
        await app.dispatch({
          'op': 'set_collection_settings',
          'expected_settings': second,
          'settings': {...second, 'tag_suggestion_count': 9},
        }, expectedDocument: app.editIdentity),
        isNotNull,
      );
      expect(app.documentServices.pending, true);
      expect(await original.exists(), false);
      expect(
        await renamed.readAsBytes(),
        persisted,
        reason: 'settings respect a lost external connection',
      );
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.collectionSettings['tag_suggestion_count'], 9);
      expect(app.collectionSettings['tag_half_life_days'], 7);
      expect(
        app.document!['parent_indicator_defaults']['4']['next_due_date'],
        true,
      );
      expect(
        app.document!['views']['1']['preferences']['4']['indicators']['total'],
        false,
      );
      expect(app.documentServices.pending, true);
      expect(app.document!['items'], before['items']);
      expect(await renamed.readAsBytes(), persisted);
      app.dispose();
      await app.documentServices.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
