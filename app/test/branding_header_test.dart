import 'dart:async';
import 'dart:io';

import 'package:app/main.dart';
import 'package:app/services/app_controller.dart';
import 'package:app/services/update_composition.dart';
import 'package:app/services/update_coordinator.dart';
import 'package:app/ui/app_brand.dart';
import 'package:app/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';
import 'update_test.dart' show Adapter, Source, candidate;

void main() {
  late DraftHarness h;
  late Directory directory;
  late UpdateCoordinator updates;
  late ProviderContainer container;
  setUp(() async {
    h = DraftHarness(memoryDrafts: true);
    await h.initialize();
    directory = await Directory.systemTemp.createTemp('ihtd-branding-ui-');
    updates = UpdateCoordinator(
      source: Source()..value = null,
      platform: Adapter(),
      stateFile: () async => File('${directory.path}/updates.json'),
    );
    await updates.ready;
    container = ProviderContainer(
      overrides: [
        appProvider.overrideWith((_) => h.app),
        updateProvider.overrideWith((_) => updates),
      ],
    );
    // The container owns these instances, including startup tests that do not
    // reach AppShell. Dispose each notifier exactly once.
    container.read(appProvider);
    container.read(updateProvider);
  });
  tearDown(() async {
    container.dispose();
    await h.app.itemDrafts.flush();
    await h.storage.diagnostics.flush();
    await h.directory.delete(recursive: true);
    await directory.delete(recursive: true);
  });
  Widget scope(Widget child) =>
      UncontrolledProviderScope(container: container, child: child);

  for (final scenario in [
    (name: 'phone', width: 390.0, scale: 1.0),
    (name: 'small enlarged text', width: 320.0, scale: 2.0),
    (name: 'desktop', width: 1440.0, scale: 1.0),
  ]) {
    testWidgets(
      '${scenario.name}: all update states use a stable slot beside the menu',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scenario.width, 820);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          scope(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scenario.scale),
                ),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: AppFileBar(app: h.app, drawer: scenario.width < 780),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final logo = find.byKey(const ValueKey('app-logo'));
        final filename = find.byKey(const ValueKey('collection-filename'));
        final slot = find.byKey(const ValueKey('update-slot'));
        final menu = find.byKey(const ValueKey('file-menu'));
        final before = [
          tester.getRect(logo),
          tester.getRect(filename),
          tester.getRect(slot),
          tester.getRect(menu),
        ];
        expect(tester.getSize(slot), const Size(48, 48));
        expect(tester.getRect(slot).right, tester.getRect(menu).left);
        expect(tester.getRect(logo).right, lessThan(tester.getRect(slot).left));
        expect(find.byTooltip('Update available'), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsNothing);
        updates.candidate = candidate();
        for (final phase in [
          UpdatePhase.available,
          UpdatePhase.downloading,
          UpdatePhase.verifying,
          UpdatePhase.ready,
          UpdatePhase.error,
        ]) {
          updates.phase = phase;
          updates.notifyListeners();
          await tester.pumpAndSettle();
          expect([
            tester.getRect(logo),
            tester.getRect(filename),
            tester.getRect(slot),
            tester.getRect(menu),
          ], before);
          final label = switch (phase) {
            UpdatePhase.ready => 'Install update',
            UpdatePhase.downloading => 'Downloading update',
            UpdatePhase.verifying => 'Verifying update',
            UpdatePhase.error => 'Update failed. Retry',
            _ => 'Update available',
          };
          expect(find.byTooltip(label), findsOneWidget);
        }
        updates.candidate = null;
        updates.notifyListeners();
        await tester.pumpAndSettle();
        expect([
          tester.getRect(logo),
          tester.getRect(filename),
          tester.getRect(slot),
          tester.getRect(menu),
        ], before);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'startup branding leaves immediately when actual initialization completes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final initialization = Completer<void>();
      await tester.pumpWidget(
        scope(IhtdApp(initialization: initialization.future)),
      );
      await tester.pump();
      expect(find.byType(IhtdStartupScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(tester.widget<IhtdLogo>(find.byType(IhtdLogo)).size, 128);
      initialization.complete();
      await tester.pumpAndSettle();
      expect(find.byType(IhtdStartupScreen), findsNothing);
      expect(find.byKey(const ValueKey('app-logo')), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed initialization keeps branded feedback without opening the app',
    (tester) async {
      final initialization = Completer<void>();
      await tester.pumpWidget(
        scope(IhtdApp(initialization: initialization.future)),
      );
      initialization.completeError(StateError('Synthetic runtime failure'));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsNothing);
      expect(
        find.text('IHTD could not start. Please restart the app.'),
        findsOneWidget,
      );
      expect(find.byType(IhtdLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
