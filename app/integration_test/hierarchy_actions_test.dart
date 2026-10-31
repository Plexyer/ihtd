import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:app/ui/item_removal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real files preserve linked originals through copy, blocked unlink, global delete and restart',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp(
        'ihtd-hierarchy-native-',
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
      final file = File('${root.path}/Tasks.ihtd');
      await app.dispatch({'op': 'new', 'path': file.path});
      Future<int> add(String title, {int? parent}) async {
        final r = await app.dispatch({
          'op': 'add_item',
          'title': title,
          'kind': 'task',
          'view_id': 1,
          'parent_id': parent,
        });
        expect(r, isNotNull, reason: app.error);
        return r!['id'] as int;
      }

      Future<int> place(
        int source,
        int? destination, {
        bool copy = false,
        int? depth = 0,
      }) async {
        final r = await app.dispatch({
          'op': 'link_or_copy',
          'source': source,
          'destination': destination,
          'mode': copy ? 'copy' : 'link',
          'depth': depth,
          'independent': false,
          'expected_revision': app.document!['revision'],
        }, expectedDocument: app.editIdentity);
        expect(r, isNotNull, reason: app.error);
        return r!['id'] as int;
      }

      final a = await add('A'), b = await add('B');
      final f = await add('Linked folder', parent: a),
          child = await add('Remove this copy only', parent: f);
      await add('Grandchild', parent: child);
      await place(f, b);
      expect(app.appearances['$child'], '2');
      final savedOriginal = jsonDecode(
        jsonEncode(app.document!['items']['$child']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => removeItemPlacement(
                  context,
                  app,
                  child,
                  f,
                  path: '$a/$f/$child',
                  action: 'unlink',
                ),
                child: const Text('Unlink selected'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Unlink selected'));
      await tester.pumpAndSettle();
      expect(
        find.text('This child belongs to a linked parent'),
        findsOneWidget,
      );
      await tester.tap(find.text('Copy parent and remove child'));
      await tester.pumpAndSettle();
      final edges = (app.document!['links'] as List).cast<Map>();
      final copied = edges.singleWhere((l) => l['parent'] == a)['child'] as int;
      expect(copied, isNot(f));
      expect(edges.any((l) => l['parent'] == copied), false);
      expect(app.document!['items']['$child'], savedOriginal);
      expect(edges.any((l) => l['parent'] == b && l['child'] == f), true);
      final trip = await add('Trip'),
          packing = await add('Packing', parent: trip),
          passport = await add('Passport', parent: trip);
      await place(passport, packing);
      final copy = await place(trip, null, copy: true, depth: 1);
      final all = (app.document!['links'] as List).cast<Map>();
      final copiedChildren = all
          .where((l) => l['parent'] == copy)
          .map((l) => l['child'] as int)
          .toList();
      final copiedPacking = copiedChildren.singleWhere(
        (id) => app.document!['items']['$id']['title'] == 'Packing',
      );
      final copiedPassport = copiedChildren.singleWhere(
        (id) => app.document!['items']['$id']['title'] == 'Passport',
      );
      expect(
        all.any(
          (l) => l['parent'] == copiedPacking && l['child'] == copiedPassport,
        ),
        true,
      );
      expect(app.appearances['$copiedPassport'], '2');
      final retained = await add('Keep elsewhere', parent: packing);
      await place(retained, b);
      final view = await app.dispatch({
        'op': 'add_view',
        'name': 'Inside packing',
        'filter': {'op': 'folder', 'folder_id': packing, 'recursive': true},
      });
      expect(
        await app.performItemAction(
          [trip, packing],
          'delete',
          confirm: (preview) async => true,
        ),
        true,
      );
      expect(app.document!['items']['$packing'], isNull);
      expect(app.document!['items']['$passport'], isNotNull);
      expect(app.document!['items']['$retained'], isNotNull);
      expect(app.issuesForView(view!['id'] as int), isNotEmpty);
      final beforeRename = await file.readAsBytes();
      await file.rename('${root.path}/Renamed.ihtd');
      await app.poll();
      await place(trip, null, copy: true, depth: 0);
      expect(app.documentServices.pending, true);
      expect(await file.exists(), false);
      final expectedDoc = jsonDecode(jsonEncode(app.document));
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.document, expectedDoc);
      expect(app.documentServices.pending, true);
      expect(
        await File('${root.path}/Renamed.ihtd').readAsBytes(),
        beforeRename,
      );
      app.dispose();
      await app.documentServices.diagnostics.flush();
      await tester.pumpWidget(const SizedBox.shrink());
      await root.delete(recursive: true);
    },
  );
}
