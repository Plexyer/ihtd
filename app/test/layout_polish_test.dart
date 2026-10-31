import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_theme.dart';
import 'package:app/ui/app_shell.dart';
import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/ui/item_editor.dart';
import 'package:app/ui/view_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _view = <String, dynamic>{
  'id': 2,
  'name': 'Travel view',
  'filter': {
    'op': 'or',
    'rules': [
      {'op': 'tag', 'tag_id': 1},
      {'op': 'priority', 'comparison': 'ge', 'value': 2},
      {'op': 'kind', 'kind': 'task'},
    ],
  },
};

void main() {
  late AppController controller;
  late Directory directory;
  late ProviderContainer container;
  late GlobalKey captureKey;

  setUp(() async {
    captureKey = GlobalKey();
    const fontPath = String.fromEnvironment('LAYOUT_FONT');
    if (fontPath.isNotEmpty) {
      await (FontLoader('Segoe UI')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
    directory = await Directory.systemTemp.createTemp('ihtd-layout-');
    PackageInfo.setMockInitialValues(
      appName: 'IHTD',
      packageName: 'dev.ihtd.app',
      version: '0.2.2',
      buildNumber: '8',
      buildSignature: '',
    );
    Future<String> command(String request) async {
      return jsonEncode({
        'ok': true,
        'snapshot': {
          'path': '${directory.path}/working.ihtd',
          'document': {
            'document_id': 'layout-test',
            'views': {
              '1': {'id': 1, 'name': 'All tasks'},
              '2': _view,
            },
            'tags': {
              '1': {'id': 1, 'name': 'Travel'},
            },
            'items': {},
          },
          'completion': {},
        },
        'data': {'rows': []},
      });
    }

    controller = AppController(
      command: command,
      polling: false,
      supportDirectory: () async => directory,
      documentServices: DocumentSaveCoordinator(
        adapter: FilesystemDocumentAdapter(command),
        supportDirectory: () async => directory,
      ),
    );
    await controller.ready;
    container = ProviderContainer(
      overrides: [appProvider.overrideWith((_) => controller)],
    );
    container.read(appProvider);
  });
  tearDown(() async {
    container.dispose();
    await controller.documentServices.diagnostics.flush();
    await directory.delete(recursive: true);
  });

  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    bool shell = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildIhtdTheme(),
          builder: (context, child) => RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: shell
              ? const AppShell()
              : Scaffold(
                  body: Builder(
                    builder: (context) => Column(
                      children: [
                        TextButton(
                          onPressed: () => showCreateItem(context, controller),
                          child: const Text('New task'),
                        ),
                        TextButton(
                          onPressed: () => showViewEditor(
                            context,
                            controller,
                            existing: _view,
                          ),
                          child: const Text('Edit view'),
                        ),
                        TextButton(
                          onPressed: () => showCreateItem(
                            context,
                            controller,
                            kind: 'folder',
                          ),
                          child: const Text('New folder'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const captureRoot = String.fromEnvironment('LAYOUT_CAPTURE');
    if (captureRoot.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(captureRoot).create(recursive: true);
      await File('$captureRoot/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> expectPixels(
    WidgetTester tester,
    Map<Offset, Color> expected,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (final entry in expected.entries) {
        final offset =
            (entry.key.dy.toInt() * image.width + entry.key.dx.toInt()) * 4;
        final actual = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        expect(actual, entry.value, reason: 'Surface pixel at ${entry.key}');
      }
      image.dispose();
    });
  }

  Future<void> open(WidgetTester tester, String label) async {
    // Controller's ready future/diagnostics were initialized in the real I/O
    // zone. Let async defaults complete before pumping the dialog animation.
    await tester.runAsync(() => tester.tap(find.text(label)));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scroll = find
        .ancestor(of: target, matching: find.byType(SingleChildScrollView))
        .first;
    final state = tester.state<ScrollableState>(
      find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
    );
    // Most targets here are near the end of the unified form. Ensure their
    // complete bounds (not just center) are visible, including wrapped buttons.
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(scroll);
    final rect = tester.getRect(target);
    expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.1));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
  }

  testWidgets(
    'focused Title label has paint clearance inside its scroll viewport',
    (tester) async {
      await host(tester);
      await open(tester, 'New task');
      expect(controller.error, isNull);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Dialog), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title *',
      );
      final scroll = find
          .ancestor(of: title, matching: find.byType(SingleChildScrollView))
          .first;
      final fieldRect = tester.getRect(title);
      final viewportRect = tester.getRect(scroll);
      // An outline's floating label paints above the TextField's layout bounds.
      expect(fieldRect.top - viewportRect.top, greaterThanOrEqualTo(8));
      expect(
        tester.getTopLeft(find.text('Title *')).dy,
        greaterThanOrEqualTo(viewportRect.top),
      );
      await tester.enterText(title, 'Keep this input');
      tester.view.viewInsets = const FakeViewPadding(bottom: 0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Keep this input',
      );
      await capture(tester, 'task-keyboard-dismissed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'view name and first rule are protected at the upper scroll limit',
    (tester) async {
      await host(tester, keyboard: 320);
      await open(tester, 'Edit view');
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'View name',
      );
      expect(
        find.ancestor(of: name, matching: find.byType(SingleChildScrollView)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'view focus and input survive switching to the short keyboard layout',
    (tester) async {
      await host(tester, size: const Size(390, 700));
      await open(tester, 'Edit view');
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'View name',
      );
      await tester.tap(name);
      await tester.enterText(name, 'Input survives reflow');
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(of: name, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, true);
      expect(editable.controller.text, 'Input survives reflow');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: name, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (name: 'pixel', size: const Size(390, 844), scale: 1.0, keyboard: 320.0),
    (name: 'small', size: const Size(320, 640), scale: 1.0, keyboard: 260.0),
    (
      name: 'landscape',
      size: const Size(844, 390),
      scale: 1.0,
      keyboard: 170.0,
    ),
    (
      name: 'large-text',
      size: const Size(390, 844),
      scale: 2.0,
      keyboard: 320.0,
    ),
    (
      name: 'short-large-text',
      size: const Size(720, 400),
      scale: 2.0,
      keyboard: 0.0,
    ),
    (name: 'desktop', size: const Size(1440, 900), scale: 1.0, keyboard: 0.0),
    (
      name: 'narrow-desktop',
      size: const Size(500, 680),
      scale: 1.0,
      keyboard: 0.0,
    ),
  ]) {
    testWidgets(
      '${scenario.name}: complete view rules/actions remain reachable',
      (tester) async {
        await host(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          keyboard: scenario.keyboard,
        );
        await open(tester, 'Edit view');
        final name = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'View name',
        );
        final scroll = find
            .ancestor(of: name, matching: find.byType(SingleChildScrollView))
            .first;
        expect(
          tester.getTopLeft(find.text('View name')).dy,
          greaterThanOrEqualTo(tester.getRect(scroll).top),
        );
        await capture(tester, 'view-${scenario.name}-top');
        await reveal(tester, find.byTooltip('Add OR condition'));
        await capture(tester, 'view-${scenario.name}-bottom');
        final save = find.widgetWithText(FilledButton, 'Save view');
        if (find
            .ancestor(of: save, matching: find.byType(SingleChildScrollView))
            .evaluate()
            .isNotEmpty) {
          await reveal(tester, save);
        }
        expect(
          tester.getRect(save).bottom,
          lessThanOrEqualTo(scenario.size.height - scenario.keyboard - 24),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      '${scenario.name}: task/folder Title and Create remain reachable',
      (tester) async {
        await host(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          keyboard: scenario.keyboard,
        );
        await open(tester, 'New folder');
        final title = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Title *',
        );
        final scroll = find
            .ancestor(of: title, matching: find.byType(SingleChildScrollView))
            .first;
        expect(
          tester.getTopLeft(find.text('Title *')).dy,
          greaterThanOrEqualTo(tester.getRect(scroll).top),
        );
        await capture(tester, 'folder-${scenario.name}-top');
        final create = find.byKey(const ValueKey('item-create-bottom'));
        if (find
            .ancestor(of: create, matching: find.byType(SingleChildScrollView))
            .evaluate()
            .isNotEmpty) {
          await reveal(tester, create);
        }
        expect(
          tester.getRect(create).bottom,
          lessThanOrEqualTo(scenario.size.height - scenario.keyboard - 24),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'header and drawer paint all safe insets using their adjacent surface',
    (tester) async {
      await host(tester, shell: true);
      final header = find.byKey(const ValueKey('header-surface'));
      expect(tester.getRect(header).top, 0);
      expect(tester.widget<ColoredBox>(header).color, AppSurfaces.light.header);
      expect(tester.getRect(header).height, 58 + 32);
      await capture(tester, 'shell-closed');
      await expectPixels(tester, {
        const Offset(100, 10): AppSurfaces.light.header,
        const Offset(100, 835): AppSurfaces.light.canvas,
      });
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      expect(tester.getRect(drawer).top, 0);
      expect(tester.getRect(drawer).bottom, 844);
      expect(
        tester.widget<Drawer>(drawer).backgroundColor,
        AppSurfaces.light.sidebar,
      );
      expect(
        tester.widget<Drawer>(drawer).surfaceTintColor,
        Colors.transparent,
      );
      expect(
        tester.getTopLeft(find.text('MY COLLECTION')).dy,
        greaterThanOrEqualTo(32),
      );
      await capture(tester, 'shell-drawer');
      await expectPixels(tester, {
        const Offset(100, 10): AppSurfaces.light.sidebar,
        const Offset(100, 835): AppSurfaces.light.sidebar,
      });
      final style = tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find
                .ancestor(
                  of: drawer,
                  matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
                )
                .first,
          )
          .value;
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarContrastEnforced, false);
      expect(tester.takeException(), isNull);
    },
  );

  test('overlay icon contrast follows each surface independently', () {
    final style = surfaceOverlays(top: Colors.black, bottom: Colors.white);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
  });
}
