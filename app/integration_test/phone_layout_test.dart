import 'dart:io';

import 'package:app/main.dart' as app;
import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/src/rust/api/simple.dart' as api;
import 'package:app/src/rust/frb_generated.dart';
import 'package:app/ui/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'phone editor flushes on Done and swipes scroll without moving items',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewInsets();
      });
      final directory = await Directory.systemTemp.createTemp(
        'ihtd-phone-test-',
      );
      await RustLib.init();
      runApp(
        ProviderScope(
          overrides: [
            appProvider.overrideWith(
              (ref) => AppController(
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
      await tester.pumpAndSettle();
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      ).read(appProvider);
      await controller.ready;
      addTearDown(() => directory.delete(recursive: true));
      expect(
        await controller.dispatch({
          'op': 'new',
          'path': '${directory.path}/phone.ihtd',
        }),
        isNotNull,
      );
      for (var i = 0; i < 20; i++) {
        expect(
          await controller.dispatch({
            'op': 'add_item',
            'kind': 'task',
            'title': 'Scroll item $i',
            'view_id': 1,
          }),
          isNotNull,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scroll item 0'));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(title, 'Saved on Done');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Saved on Done'), findsOneWidget);
      expect(controller.error, isNull);
      final revision = controller.document!['revision'];
      final links = '${controller.document!['links']}';
      await tester.drag(find.text('Saved on Done'), const Offset(0, -280));
      await tester.pumpAndSettle();
      expect(controller.document!['revision'], revision);
      expect('${controller.document!['links']}', links);
      expect(tester.takeException(), isNull);
      // Exercise the phone gesture and drop acceptance, not just the command.
      await controller.dispatch({
        'op': 'new',
        'path': '${directory.path}/descendant.ihtd',
      });
      Future<int> add(String title, String kind, [int? parent]) async {
        final result = await controller.dispatch({
          'op': 'add_item',
          'kind': kind,
          'title': title,
          'parent_id': parent,
          'view_id': 1,
        });
        return result!['id'] as int;
      }

      final moved = await add('test2', 'task');
      final branch = await add('test', 'folder', moved);
      final target = await add('Destination', 'task', branch);
      await tester.pumpAndSettle();
      final start = tester.getCenter(find.byKey(ValueKey('drag-$moved')));
      final end = tester.getCenter(
        find.byKey(ValueKey('into-$moved/$branch/$target')),
      );
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(controller.document!['root_order'], [branch]);
      expect(controller.document!['links'], [
        {'parent': branch, 'child': target},
        {'parent': target, 'child': moved},
      ]);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('MY COLLECTION')).dy,
        greaterThanOrEqualTo(32),
      );
      // Exercise the shared dialog through the real controller/bridge, with
      // enough rules to scroll and an actual saved-view edit.
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      final addedView = await controller.dispatch({
        'op': 'add_view',
        'name': 'Layout check',
        'filter': {
          'op': 'or',
          'rules': [
            {'op': 'priority', 'comparison': 'ge', 'value': 2},
            {'op': 'kind', 'kind': 'task'},
            {'op': 'kind', 'kind': 'folder'},
          ],
        },
      });
      await controller.selectView(addedView!['id'] as int);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit this view'));
      await tester.pumpAndSettle();
      final viewName = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'View name',
      );
      await tester.enterText(viewName, 'Layout verified');
      final scroll = find
          .ancestor(of: viewName, matching: find.byType(SingleChildScrollView))
          .first;
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add condition'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save view'));
      await tester.pumpAndSettle();
      expect(find.text('Layout verified'), findsOneWidget);
      await controller.selectView(1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      final newTitle = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title *',
      );
      final titleScroll = find
          .ancestor(of: newTitle, matching: find.byType(SingleChildScrollView))
          .first;
      expect(
        tester.getTopLeft(find.text('Title *')).dy,
        greaterThanOrEqualTo(tester.getRect(titleScroll).top),
      );
      await tester.enterText(newTitle, 'Created with keyboard');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Created with keyboard'), findsOneWidget);
      expect(controller.error, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
