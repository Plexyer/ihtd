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
    'private draft survives restart and stays bound to its own working copy across identical UUIDs',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp('ihtd-draft-native-');
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
      final original = '${root.path}/Original.ihtd';
      await app.dispatch({'op': 'new', 'path': original});
      final created = await app.dispatch({
        'op': 'add_item',
        'kind': 'task',
        'title': 'Saved title',
        'notes': 'Saved notes',
        'view_id': 1,
      });
      final id = created!['id'] as int;
      await app.selectItem(id);
      app.changeItemDraft('notes', 'Retained unfinished notes');
      app.changeItemDraft('auto_complete', true);
      await app.itemDrafts.flush();
      expect(app.document!['items']['$id']['notes'], 'Saved notes');
      final originalBytes = await File(original).readAsBytes();
      final owner = app.editIdentity;
      app.dispose();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.itemDraft, isNull);
      expect(app.recoveredDrafts, hasLength(1));
      final draft = app.recoveredDrafts.single;
      final copy = '${root.path}/Same UUID copy.ihtd';
      await File(original).copy(copy);
      await app.dispatch({'op': 'open', 'path': copy});
      expect(app.editIdentity.documentId, owner.documentId);
      expect(app.editIdentity.workingPath, isNot(owner.workingPath));
      app.confirmDocumentAction = (_, _) async => true;
      expect(await app.restoreItemDraft(draft), true);
      expect(app.editIdentity, owner);
      expect(app.document!['items']['$id']['notes'], 'Saved notes');
      expect(app.itemDraft!.values['notes'], 'Retained unfinished notes');
      expect(await app.saveItemDraft(), true);
      expect(app.itemDraft, isNull);
      expect(app.document!['items']['$id']['auto_complete'], true);
      expect(await File(copy).readAsBytes(), originalBytes);
      expect(app.documentServices.pending, true);
      expect(
        await File(original).readAsBytes(),
        originalBytes,
        reason: 'restored drafts keep the destination confirmation barrier',
      );
      await app.reconnectDocument();
      expect(app.documentServices.pending, false);
      await app.dispatch({'op': 'open', 'path': original});
      expect(
        app.document!['items']['$id']['notes'],
        'Retained unfinished notes',
      );
      expect(app.recoveredDrafts, isEmpty);
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
