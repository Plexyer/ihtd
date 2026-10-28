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
    'real SQLite upgrade, sibling backup, guarded publication and restart',
    (tester) async {
      await RustLib.init();
      final temp = await Directory.systemTemp.createTemp(
        'ihtd-native-migration-',
      );
      final source = File('${temp.path}/Tasks.ihtd');
      final original = await File('test/fixtures/migration-schema1.sqlite')
          .readAsBytes();
      await source.writeAsBytes(original);
      final support = Directory('${temp.path}/support');
      Future<String> command(String request) => api.command(request: request);
      DocumentSaveCoordinator storage() => DocumentSaveCoordinator(
        adapter: FilesystemDocumentAdapter(command),
        supportDirectory: () async => support,
      );
      final coordinator = storage();
      final controller = AppController(
        documentServices: coordinator,
        command: command,
        supportDirectory: () async => support,
        polling: false,
      );
      await controller.ready;
      await controller.dispatch({'op': 'open', 'path': source.path});
      expect(controller.error, isNull);
      expect(coordinator.pending, false);
      expect(controller.document?['revision'], 42);
      expect(controller.document?['items']['4']['notes'], 'Synthetic notes 日本');
      expect((controller.document?['links'] as List).length, 3);
      final backups = await temp
          .list()
          .where((file) => file.path.contains('IHTD-before-upgrade-'))
          .toList();
      expect(backups.length, 1);
      expect(await File(backups.single.path).readAsBytes(), original);
      expect((await File(source.path).readAsBytes())[63], 2);
      final probe = jsonDecode(
        await command(
          jsonEncode({
            'op': 'migration',
            'action': 'probe',
            'source': backups.single.path,
          }),
        ),
      ) as Map;
      expect(probe['data']['from'], 1);
      final jobs = await coordinator.migrations.recoveryAttempts();
      expect(jobs.single['status'], 'completed');
      controller.dispose();
      await coordinator.diagnostics.flush();
      final restored = storage();
      final reopened = AppController(
        documentServices: restored,
        command: command,
        supportDirectory: () async => support,
        polling: false,
      );
      await reopened.ready;
      expect(reopened.error, isNull);
      expect(reopened.document?['items']['4']['title'], 'Pack passport');
      expect(restored.migrations.hasIssue, false);
      expect(
        (await temp
                .list()
                .where((file) => file.path.contains('IHTD-before-upgrade-'))
                .toList())
            .length,
        1,
      );
      reopened.dispose();
      await restored.diagnostics.flush();
      await temp.delete(recursive: true);
    },
  );
}
