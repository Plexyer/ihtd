import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:app/ui/summary_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real summaries preserve old files, private drafts, date refresh and disconnected restart',
    (tester) async {
      await RustLib.init();
      final root = await Directory.systemTemp.createTemp(
        'ihtd-summary-native-',
      );
      final support = Directory('${root.path}/support');
      var day = DateTime(2026, 11, 30);
      Future<String> command(String request) => api.command(request: request);
      AppController start() => AppController(
        command: command,
        polling: false,
        now: () => day,
        supportDirectory: () async => support,
        documentServices: DocumentSaveCoordinator(
          adapter: FilesystemDocumentAdapter(command),
          supportDirectory: () async => support,
        ),
      );
      var app = start();
      await app.ready;
      final source = File('${root.path}/Original.ihtd');
      final distributed = await File('test/fixtures/migration-schema2.sqlite')
          .readAsBytes();
      await source.writeAsBytes(distributed);
      expect(
        await app.dispatch({'op': 'open', 'path': source.path}),
        isNotNull,
        reason: app.error,
      );
      Map<String, dynamic> metrics(int id) => Map<String, dynamic>.from(
        app.rows.firstWhere((r) => r['id'] == id)['summary'] as Map,
      );
      final revision = app.document!['revision'];
      final working = File(app.editIdentity.workingPath!);
      final privateBytes = await working.readAsBytes();
      expect(metrics(2), {'total': 1, 'high_priority': 1});
      expect(metrics(3), {
        'total': 1,
        'high_priority': 1,
      }); // shared child counted once per parent
      await app.refreshRows();
      expect(await source.readAsBytes(), distributed);
      expect(await working.readAsBytes(), privateBytes);
      expect(app.document!['revision'], revision);

      app.completedOnly = true;
      await app.refreshRows();
      expect(metrics(2), {'total': 1, 'high_priority': 0});
      app.completedOnly = false;
      await app.selectItem(4);
      app.changeItemDraft('notes', 'Unfinished summary test draft');
      final old = jsonDecode(
        jsonEncode(app.collectionSettings),
      ) as Map<String, dynamic>;
      final settings = jsonDecode(jsonEncode(old)) as Map<String, dynamic>;
      settings['indicators'] = {
        'total': true,
        'completed_ratio': true,
        'high_priority': true,
        'medium_priority': true,
        'low_priority': true,
        'next_due_date': true,
      };
      expect(
        await app.dispatch({
          'op': 'set_collection_settings',
          'expected_settings': old,
          'settings': settings,
        }, expectedDocument: app.editIdentity),
        isNotNull,
        reason: app.error,
      );
      expect(metrics(2), {
        'total': 2,
        'completed': 1,
        'high_priority': 1,
        'medium_priority': 0,
        'low_priority': 0,
        'next_due_date': '2026-12-01',
      });
      expect(app.document!['items']['4']['notes'], 'Synthetic notes 日本');
      expect(app.itemDraft!.dirty, true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SummaryIndicators(summary: metrics(2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total: 1 / 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      final beforeDayChange = await source.readAsBytes();
      final beforeDayRevision = app.document!['revision'];
      day = DateTime(2026, 12, 2);
      await app.poll();
      expect(metrics(2)['next_due_date'], isNull);
      expect(await source.readAsBytes(), beforeDayChange);
      expect(app.document!['revision'], beforeDayRevision);
      expect(app.itemDraft!.values['notes'], 'Unfinished summary test draft');

      final renamed = await source.rename('${root.path}/Renamed.ihtd');
      expect(
        await app.dispatch({
          'op': 'set_indicator_settings',
          'item_id': 2,
          'view_id': 1,
          'expected_parent': {},
          'expected_view': {},
          'parent_overrides': {},
          'view_overrides': {'total': false},
        }, expectedDocument: app.editIdentity),
        isNotNull,
        reason: app.error,
      );
      expect(metrics(2).containsKey('total'), false);
      expect(metrics(2).containsKey('completed'), false);
      expect(app.documentServices.pending, true);
      expect(await renamed.readAsBytes(), beforeDayChange);
      await app.checkpointItemDraft();
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      app = start();
      await app.ready;
      expect(app.documentServices.pending, true);
      expect(metrics(2).containsKey('total'), false);
      expect(metrics(2)['high_priority'], 1);
      expect(app.recoveredDrafts, isNotEmpty);
      expect(app.document!['items']['4']['notes'], 'Synthetic notes 日本');
      expect(await source.exists(), false);
      expect(await renamed.readAsBytes(), beforeDayChange);
      app.dispose();
      await app.itemDrafts.flush();
      await app.documentServices.diagnostics.flush();
      await root.delete(recursive: true);
    },
  );
}
