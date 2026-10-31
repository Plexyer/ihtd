import 'package:app/ui/item_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';
import 'support/settle_controller.dart';

void main() {
  late DraftHarness h;
  setUp(() async {
    h = DraftHarness(memoryDrafts: true);
    await h.initialize();
  });
  tearDown(() async {
    await h.dispose();
  });
  Future<void> settle(WidgetTester tester) => settleController(tester, h.app);

  Future<void> closeWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var complete = false;
    h.app.itemDrafts.flush().then((_) => complete = true);
    for (var i = 0; i < 150 && !complete; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      complete,
      true,
      reason: 'finish private IO before leaving the fake widget clock',
    );
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Widget editor() => MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: h.app,
        builder: (_, _) => ItemEditor(app: h.app),
      ),
    ),
  );
  testWidgets(
    'checkpoint and unrelated saved changes preserve selection/composition; Cancel never publishes the draft',
    (tester) async {
      await tester.runAsync(() => h.app.selectItem(3));
      await tester.pumpWidget(editor());
      await tester.tap(field('Notes'));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'A draft note',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 4),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => h.app.dispatch({'op': 'add_tag', 'name': 'Separate tag'}),
      );
      await tester.pump();
      final value = tester.widget<TextField>(field('Notes')).controller!.value;
      expect(value.selection.baseOffset, 3);
      expect(value.composing, const TextRange(start: 2, end: 4));
      expect(h.doc['items']['3']['notes'], 'Saved notes');
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(TextButton, 'Cancel')),
      );
      await settle(tester);
      expect(h.app.itemDraft, null);
      expect(h.doc['items']['3']['notes'], 'Saved notes');
      await closeWidget(tester);
    },
  );
  testWidgets(
    'Back/Escape presents Save Discard Keep editing; Keep editing retains the window',
    (tester) async {
      await tester.runAsync(() => h.app.selectItem(3));
      await tester.pumpWidget(editor());
      await tester.enterText(field('Title'), 'Unfinished');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Save unfinished changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(field('Title'), findsOneWidget);
      expect(h.app.itemDraft?.dirty, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      await tester.runAsync(() => tester.tap(find.text('Discard')));
      await settle(tester);
      expect(h.app.itemDraft, null);
      expect(h.doc['items']['3']['title'], 'Saved title');
      await closeWidget(tester);
    },
  );
  testWidgets(
    'outside invalid editor stays open; Save closes the complete route with no empty shell',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => h.app.selectItem(3));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showItemDraftDialog(context, h.app),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(field('Title'), '');
      await tester.runAsync(() => tester.tapAt(const Offset(2, 300)));
      await settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Enter a title.'), findsOneWidget);
      await tester.enterText(field('Title'), 'Saved through modal');
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
      );
      await settle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(h.app.itemDraft, null);
      expect(h.doc['items']['3']['title'], 'Saved through modal');
      await closeWidget(tester);
    },
  );
}
