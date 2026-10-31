import 'package:app/ui/item_editor.dart';
import 'package:app/ui/item_editor_style.dart';
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

  for (final folder in [false, true]) {
    for (final children in [false, true]) {
      testWidgets(
        '${folder ? "folder" : "task"}, children=$children: only applicable sections appear',
        (tester) async {
          final id = folder ? 2 : 3;
          if (children) {
            h.doc['items']['4'] = <String, Object?>{
              ...h.doc['items']['3'] as Map,
              'id': 4,
              'title': 'Child',
            };
            h.doc['links'] = [
              {'parent': id, 'child': 4, 'position': 0},
            ];
            await tester.runAsync(() => h.app.poll());
          }
          await tester.runAsync(() => h.app.selectItem(id));
          final original = h.app.document.toString();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: h.app,
                  builder: (_, _) => ItemEditor(app: h.app),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Visibility in this view'),
            folder || children ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Completed children'),
            children ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Hide from unfinished'),
            folder ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Completion'),
            folder ? findsNothing : findsOneWidget,
          );
          expect(find.text('Details'), findsOneWidget);
          expect(find.text('Display and sorting'), findsOneWidget);
          expect(find.text('Item actions'), findsOneWidget);
          expect(find.byType(ItemEditorSection), findsWidgets);
          expect(h.app.document.toString(), original);
          expect(h.adapter.writes, 0);
          expect(tester.takeException(), null);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'section rules wrap long headings with large text in a narrow editor',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 220,
                  child: ItemEditorSection(
                    'Parents and top-level placement',
                    trailing: IconButton(
                      onPressed: null,
                      icon: Icon(Icons.add),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.byType(Divider), findsNWidgets(2));
      expect(
        tester.getSize(find.text('Parents and top-level placement')).height,
        greaterThan(32),
      );
    },
  );
}
