import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/ui/document_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'migration_safety_test.dart' show MigrationAdapter;

void main() {
  testWidgets(
    'failed first open exposes warning, recovery and log export without replaying writes',
    (tester) async {
      late Directory temp;
      late MigrationAdapter adapter;
      late DocumentSaveCoordinator storage;
      late AppController app;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('ihtd-migration-ui-');
        adapter = MigrationAdapter('filesystem');
        storage = DocumentSaveCoordinator(
          adapter: adapter,
          supportDirectory: () async => temp,
        );
        app = AppController(
          documentServices: storage,
          supportDirectory: () async => temp,
          polling: false,
          command: (_) async => jsonEncode({'ok': true, 'data': {}}),
        );
        await app.ready;
        await storage.migrations.fail({
          'id': '12345-abc',
          'from': 1,
          'target': 2,
          'status': 'running',
          'stage': 'backup',
          'started': DateTime.now().toUtc().toIso8601String(),
          'backups': [],
        }, 'backup_required');
      });
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocumentStatus(app: app)),
        ),
      );
      expect(app.document, isNull);
      expect(app.documentIssue, true);
      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(DocumentStatus),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.color, const Color(0xffffefbd));
      await tester.tap(find.text('Collection upgrade needs attention'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentIssueDialog), findsOneWidget);
      expect(
        find.textContaining('Choose an authorized backup folder'),
        findsOneWidget,
      );
      expect(find.text('Choose authorized backup folder…'), findsOneWidget);
      expect(find.text('Upgrade recovery files…'), findsOneWidget);
      expect(find.text('Retry / confirm file…'), findsNothing);
      expect(adapter.publications, 0);
      expect(storage.migrations.hasIssue, true);
      expect(
        await tester.runAsync(storage.migrations.exportLog),
        contains('backup_required'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      await tester.runAsync(() async {
        await storage.diagnostics.flush();
        await temp.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
