import 'package:app/ui/item_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';

void main() {
  late DraftHarness h;
  setUp(() async {
    h = DraftHarness(memoryDrafts: true);
    await h.initialize();
  });
  tearDown(() => h.dispose());
  final top = find.byKey(const ValueKey('item-create-top'));
  final bottom = find.byKey(const ValueKey('item-create-bottom'));
  Finder title() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Title *',
  );
  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(420, 820),
    double scale = 1,
    String kind = 'task',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    expect(
      await h.app.beginCreateDraft({
        'tag_ids': [],
        'requirements': [],
      }, kind: kind),
      true,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: h.app,
            builder: (_, _) => ItemEditor(app: h.app),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'extra Create follows actual height without losing title focus or composing text',
    (tester) async {
      await host(tester);
      expect(top, findsNothing);
      expect(bottom, findsOneWidget);
      await tester.tap(title());
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Unfinished title',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 2, end: 6),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(title()).controller!;
      final before = controller.value;
      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      await tester.pumpAndSettle();
      expect(top.hitTestable(), findsOneWidget);
      expect(bottom, findsOneWidget);
      expect(tester.widget<TextField>(title()).controller, same(controller));
      expect(controller.value, before);
      expect(tester.testTextInput.isVisible, true);
      expect(h.app.itemDraft!.values['title'], 'Unfinished title');
      expect(h.doc['items'].length, 2);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(top, findsNothing);
      expect(controller.value, before);
      tester.view.physicalSize = const Size(600, 440);
      await tester.pumpAndSettle();
      expect(top.hitTestable(), findsOneWidget);
      expect(controller.value, before);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final kind in ['task', 'folder']) {
    testWidgets('top Create commits one $kind and closes the editor', (
      tester,
    ) async {
      await host(tester, size: const Size(420, 440), kind: kind);
      await tester.enterText(title(), 'New $kind');
      expect(top.hitTestable(), findsOneWidget);
      expect(bottom, findsOneWidget);
      final id = h.doc['next_id'];
      await tester.runAsync(() => tester.tap(top));
      await settle(tester);
      expect(h.app.itemDraft, null);
      expect(h.doc['items']['$id']['title'], 'New $kind');
      expect(h.doc['items']['$id']['kind'], kind);
      expect(h.commands.where((c) => c['op'] == 'save_item_draft').length, 1);
      expect(h.adapter.writes, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'top and bottom Create share validation and busy state; a failed Save retains the draft',
    (tester) async {
      await host(tester, size: const Size(420, 440));
      h.app.busy = true;
      h.app.notifyListeners();
      await tester.pump();
      expect(tester.widget<FilledButton>(top).onPressed, null);
      expect(tester.widget<FilledButton>(bottom).onPressed, null);
      h.app.busy = false;
      h.app.notifyListeners();
      await tester.pump();
      await tester.tap(top);
      await tester.pumpAndSettle();
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(h.doc['items'].length, 2);
      await tester.enterText(title(), 'Retry creation');
      h.failSave = true;
      await tester.runAsync(() => tester.tap(top));
      await settle(tester);
      expect(h.app.itemDraft, isNotNull);
      expect(h.doc['items'].length, 2);
      h.failSave = false;
      await tester.ensureVisible(bottom);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(bottom));
      await settle(tester);
      expect(h.app.itemDraft, null);
      expect(h.doc['items'].length, 3);
      expect(h.adapter.writes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'very short layouts and enlarged text keep top Create reachable',
    (tester) async {
      await host(tester, size: const Size(320, 280), scale: 2);
      expect(top.hitTestable(), findsOneWidget);
      expect(bottom, findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('existing items retain Save without extra Create', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 440);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await h.app.selectItem(3);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ItemEditor(app: h.app)),
      ),
    );
    expect(top, findsNothing);
    expect(bottom, findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
