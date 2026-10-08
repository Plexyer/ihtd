import 'dart:io';

import 'package:app/main.dart' as app;
import 'package:app/services/app_controller.dart';
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
      });
      await app.main();
      await tester.pumpAndSettle();
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      ).read(appProvider);
      await controller.ready;
      final directory = await Directory.systemTemp.createTemp(
        'ihtd-phone-test-',
      );
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
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('MY COLLECTION')).dy,
        greaterThanOrEqualTo(32),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
