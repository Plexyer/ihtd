import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app/main.dart' as app;
import 'package:app/services/app_controller.dart';
import 'package:app/ui/app_shell.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create through UI, shared completion, filters, and reopen', (
    tester,
  ) async {
    // Exercise the desktop detail panel regardless of the runner's display/DPI.
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await app.main();
    await tester.pumpAndSettle();
    expect(find.text('Create collection'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final controller = container.read(appProvider);
    await controller.ready;
    final directory = await Directory.systemTemp.createTemp('ihtd-ui-test-');
    final path = '${directory.path}/collection.ihtd';
    expect(await controller.dispatch({'op': 'new', 'path': path}), isNotNull);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add task'));
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title *',
    );
    await tester.enterText(title, 'Shared task');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    var items = Map<String, dynamic>.from(controller.document!['items'] as Map);
    final task = items.values.first['id'] as int;
    await controller.selectItem(task);
    await tester.pumpAndSettle();
    final editTitle = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title',
    );
    await tester.enterText(editTitle, 'Shared task edited');
    expect(await controller.finishDraft(), true);
    await tester.pumpAndSettle();
    expect(
      controller.document!['items']['$task']['title'],
      'Shared task edited',
    );
    final a = await controller.dispatch({
      'op': 'add_item',
      'kind': 'task',
      'title': 'Project A',
      'view_id': 1,
    });
    final b = await controller.dispatch({
      'op': 'add_item',
      'kind': 'task',
      'title': 'Project B',
      'view_id': 1,
    });
    Future<void> dragPlacement(String source, String target) async {
      await tester.pumpAndSettle();
      final start = tester.getCenter(find.byKey(ValueKey('drag-$source')));
      final end = tester.getCenter(find.byKey(ValueKey(target)));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
    }

    await dragPlacement('$task', 'into-${a!['id']}');
    expect(
      (controller.document!['links'] as List).any(
        (l) => l['parent'] == a['id'] && l['child'] == task,
      ),
      true,
    );
    await controller.dispatch({
      'op': 'link',
      'parent': b!['id'],
      'child': task,
    });
    await dragPlacement('${a['id']}/$task', 'top-level-drop');
    expect(controller.rows.where((r) => r['id'] == task).length, 2);
    expect(
      (controller.document!['links'] as List).any(
        (l) => l['parent'] == b['id'] && l['child'] == task,
      ),
      true,
    );
    await dragPlacement('$task', 'into-${a['id']}');
    await dragPlacement('${b['id']}', 'before-${a['id']}');
    expect(controller.rows.first['id'], b['id']);
    await controller.dispatch({
      'op': 'set_auto_complete',
      'id': a['id'],
      'enabled': true,
    });
    await controller.dispatch({
      'op': 'set_completed',
      'id': task,
      'completed': true,
      'confirm_descendants': false,
    });
    items = Map<String, dynamic>.from(controller.document!['items'] as Map);
    expect(items['${a['id']}']['completed'], true);
    expect(items['${b['id']}']['completed'], false);
    controller.setCompletedOnly(true);
    await tester.pumpAndSettle();
    expect(controller.rows.where((r) => r['id'] == task).length, 2);
    final tag = await controller.dispatch({'op': 'add_tag', 'name': 'Work'});
    final view = await controller.dispatch({
      'op': 'add_view',
      'name': 'Work',
      'filter': {'op': 'tag', 'tag_id': tag!['id']},
    });
    final defaults = await controller.dispatch({
      'op': 'creation_defaults',
      'view_id': view!['id'],
    });
    expect(defaults!['tag_ids'], [tag['id']]);
    final snapshot = controller.document!;
    expect(await controller.dispatch({'op': 'open', 'path': path}), isNotNull);
    expect(controller.document, snapshot);
    expect(await File(path).length(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
