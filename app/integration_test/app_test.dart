import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app/main.dart' as app;
import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/ui/app_shell.dart';
import 'package:app/src/rust/frb_generated.dart';

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
    final directory = await Directory.systemTemp.createTemp('ihtd-ui-test-');
    Future<void> start([String? initialPath]) async {
      await RustLib.init();
      runApp(
        ProviderScope(
          overrides: [
            appProvider.overrideWith(
              (ref) => AppController(
                // This test drives poll explicitly after filesystem changes.
                // A periodic poll already in flight can skip that call and
                // race its immediate assertions, independently of UI layout.
                polling: false,
                initialDocumentPath: initialPath,
                supportDirectory: () async =>
                    Directory('${directory.path}/support'),
                documentServices: DocumentSaveCoordinator(
                  adapter: FilesystemDocumentAdapter(
                    (request) => api.command(request: request),
                  ),
                  supportDirectory: () async =>
                      Directory('${directory.path}/support'),
                ),
              ),
            ),
          ],
          child: const app.IhtdApp(),
        ),
      );
    }

    await start();
    await tester.pumpAndSettle();
    expect(find.text('Create collection'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final controller = container.read(appProvider);
    await controller.ready;
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
    var snapshot = controller.document!;
    expect(await controller.dispatch({'op': 'open', 'path': path}), isNotNull);
    expect(controller.document, snapshot);
    expect(await File(path).length(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Real domain + shared UI: Delete previews cascade but retain shared
    // branches; Unlink removes the selected explicit root immediately.
    controller.setCompletedOnly(false);
    await controller.selectView(1);
    Future<int> addRemovalItem(
      String title, {
      String kind = 'task',
      int? parent,
    }) async {
      final result = await controller.dispatch({
        'op': 'add_item',
        'view_id': 1,
        'kind': kind,
        'title': title,
        'parent_id': parent,
      });
      expect(result, isNotNull);
      return result!['id'] as int;
    }

    final trip = await addRemovalItem('Removal trip', kind: 'folder');
    final unique = await addRemovalItem('Only in trip', parent: trip);
    final kept = await addRemovalItem(
      'Shared packing folder',
      kind: 'folder',
      parent: trip,
    );
    final keptChild = await addRemovalItem(
      'Keep through shared branch',
      parent: kept,
    );
    await controller.dispatch({'op': 'link', 'parent': b['id'], 'child': kept});
    final affectedView = await controller.dispatch({
      'op': 'add_view',
      'name': 'Inside removal trip',
      'filter': {'op': 'folder', 'folder_id': trip},
    });
    await controller.selectItem(trip);
    Future<void> openRemovalMenu(String rowPath, String label) async {
      await tester.pumpAndSettle();
      final menu = find.byKey(ValueKey('menu-$rowPath'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final removal = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'remove',
      );
      expect(
        find.descendant(of: removal, matching: find.text(label)),
        findsOneWidget,
      );
      await tester.tap(removal);
      await tester.pumpAndSettle();
    }

    await openRemovalMenu('$trip', 'Delete');
    expect(find.text('Delete “Removal trip”?'), findsOneWidget);
    expect(find.textContaining('These shared branches remain'), findsOneWidget);
    final beforeCancel = controller.document!;
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.document, beforeCancel);
    await openRemovalMenu('$trip', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(controller.selectedItemId, isNull);
    expect(controller.document!['items']['$trip'], isNull);
    expect(controller.document!['items']['$unique'], isNull);
    expect(controller.document!['items']['$kept'], isNotNull);
    expect(controller.document!['items']['$keptChild'], isNotNull);
    await controller.selectView(affectedView!['id'] as int);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('view-rule-warning')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-rule-warning')));
    await tester.pumpAndSettle();
    expect(find.text('Deleted container (#$trip)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await controller.dispatch({
      'op': 'edit_view',
      'id': affectedView['id'],
      'name': 'Inside removal trip',
      'filter': {'op': 'all'},
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('view-rule-warning')), findsNothing);
    await controller.selectView(1);
    await controller.dispatch({'op': 'link', 'parent': a['id'], 'child': kept});
    await controller.dispatch({
      'op': 'move_item',
      'id': kept,
      'source_parent': a['id'],
      'destination_parent': null,
    });
    await controller.selectItem(kept);
    await openRemovalMenu('$kept', 'Unlink');
    expect(controller.selectedItemId, kept);
    expect(controller.document!['root_order'], isNot(contains(kept)));
    expect(controller.placements['$kept']['parents'], [b['id']]);
    expect(find.text('Delete “Shared packing folder”?'), findsNothing);
    snapshot = controller.document!;
    expect(await controller.dispatch({'op': 'open', 'path': path}), isNotNull);
    expect(controller.document, snapshot);
    expect(controller.document!['items']['$trip'], isNull);
    expect(controller.document!['items']['$keptChild'], isNotNull);

    // Exercise the actual filesystem adapter: renaming cannot recreate the old
    // path or publish edits merely because the task/editor is opened again.
    final renamedPath = '${directory.path}/renamed collection.ihtd';
    final externalBefore = await File(path).readAsBytes();
    await File(path).rename(renamedPath);
    await controller.poll();
    expect(controller.documentServices.hasIssue, true);
    expect(
      await controller.dispatch({
        'op': 'add_tag',
        'name': 'Pending after rename',
      }),
      isNotNull,
    );
    expect(
      await controller.removePlacement(
        keptChild,
        kept,
        confirmDelete: (_) async => true,
      ),
      true,
    );
    expect(controller.document!['items']['$keptChild'], isNull);
    await controller.selectItem(task);
    await controller.poll();
    expect(controller.documentServices.pending, true);
    expect(await File(path).exists(), false);
    expect(await File(renamedPath).readAsBytes(), externalBefore);
    final selected = {
      'reference': controller.documentServices.adapter
          .referenceFor(renamedPath)
          .toJson(),
    };
    final approved = {
      ...selected,
      ...(await controller.documentServices.inspect(selected)),
      'explicitSelection': true,
    };
    expect(await controller.documentServices.confirm(selected: approved), true);
    expect(controller.documentServices.pending, false);
    expect(controller.path, renamedPath);
    snapshot = controller.document!;

    // Explorer passes the full document path as a single argument. Exercise a
    // fresh controller with a different path, spaces and non-ASCII characters.
    final launchPath = '${directory.path}/日本 travel collection.ihtd';
    await File(controller.path!).copy(launchPath);
    await tester.pumpWidget(const SizedBox.shrink());
    RustLib.dispose();
    await start(launchPath);
    await tester.pumpAndSettle();
    final launched = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(appProvider);
    await launched.ready;
    // Initialization can finish after the first settle while native file IO
    // is pending. Render its final notification before checking the UI.
    await tester.pumpAndSettle();
    expect(launched.error, isNull);
    expect(launched.path, launchPath);
    expect(launched.document, snapshot);
    expect(find.text('Create collection'), findsNothing);
    expect(tester.takeException(), isNull);

    // Windows installer checks use this real collection as preservation data.
    final installerFixture =
        Platform.environment['IHTD_INSTALLER_TEST_COLLECTION'];
    if (installerFixture != null) await File(launchPath).copy(installerFixture);
  });
}
