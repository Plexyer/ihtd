import 'dart:convert';
import 'dart:async';

import 'package:app/ui/item_editor.dart';
import 'package:app/ui/tag_selector.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';
import 'support/settle_controller.dart';

class TagHarness extends DraftHarness {
  TagHarness() : super(memoryDrafts: true);
  Completer<void>? rankGate;
  @override
  Future<String> command(String input) async {
    final request = jsonDecode(input) as Map<String, dynamic>;
    if (request['op'] != 'rank_tags') return super.command(input);
    commands.add(request);
    if (rankGate != null) await rankGate!.future;
    return jsonEncode({
      'ok': true,
      'snapshot': snapshot(),
      'data': {
        'order': [13, 14, 15, 16, 17, 10, 11, 12],
      },
    });
  }
}

void main() {
  late TagHarness h;
  setUp(() async {
    h = TagHarness();
    h.doc['tags'] = <String, dynamic>{
      for (var id = 10; id <= 17; id++)
        '$id': <String, dynamic>{'id': id, 'name': 'Tag ${id - 10}'},
    };
    h.doc['next_id'] = 20;
    h.doc['items']['3']['tag_ids'] = [10, 11, 12];
    await h.initialize();
    // Override only this setting; the fake snapshot supplies the Rust defaults.
    h.doc['collection_settings'] = {
      ...h.app.collectionSettings,
      'tag_suggestion_count': 2,
    };
    await h.app.dispatch({'op': 'snapshot'});
    await h.app.selectItem(3);
  });
  tearDown(() async => h.dispose());

  Future<void> settle(WidgetTester tester) => settleController(tester, h.app);

  Future<void> host(
    WidgetTester tester, {
    bool editor = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIhtdTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: h.app,
            builder: (_, _) => editor
                ? ItemEditor(app: h.app)
                : h.app.itemDraft == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: TagSelector(
                      app: h.app,
                      sessionId: h.app.itemDraft!.sessionId,
                      selected: List<int>.from(
                        h.app.itemDraft!.values['tag_ids'] as List,
                      ),
                      disabled: h.app.busy,
                    ),
                  ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Select other…'));
    await settle(tester);
  }

  Finder search() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Search tags',
  );

  test(
    'ranking stays read-only and rejects another working copy sharing a UUID',
    () async {
      h.rankGate = Completer<void>();
      final owner = h.app.editIdentity;
      final pending = h.app.rankedTags(owner);
      expect(h.app.busy, false);
      h.working = '${h.directory.path}/another-working-copy.ihtd';
      await h.app.dispatch({'op': 'snapshot'});
      expect(h.app.editIdentity.documentId, owner.documentId);
      expect(h.app.editIdentity.workingPath, isNot(owner.workingPath));
      h.rankGate!.complete();
      expect(await pending, isNull);
      expect(h.adapter.writes, 0);
    },
  );

  testWidgets(
    'all selected tags stay above the divider and do not consume suggestion slots; edits stay private',
    (tester) async {
      await host(tester);
      expect(find.byKey(const ValueKey('selected-tag-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-tag-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-tag-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggested-tag-13')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggested-tag-14')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggested-tag-15')), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('selected-tag-10'))).dy,
        lessThan(tester.getCenter(find.byType(Divider)).dy),
      );
      await tester.tap(find.byKey(const ValueKey('suggested-tag-13')));
      await settle(tester);
      expect(find.byKey(const ValueKey('selected-tag-13')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggested-tag-15')), findsOneWidget);
      expect(h.doc['items']['3']['tag_ids'], [10, 11, 12]);
      expect(h.adapter.writes, 0);
      h.doc['collection_settings']['tag_suggestion_count'] = 0;
      await tester.runAsync(() => h.app.dispatch({'op': 'snapshot'}));
      await settle(tester);
      expect(
        find.byWidgetPredicate((w) => w is FilterChip && !w.selected),
        findsNothing,
      );
      expect(find.text('Select other…'), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-tag-13')), findsOneWidget);
      await tester.runAsync(() => h.app.discardItemDraft());
    },
  );

  testWidgets(
    'search supports multiple choices; Cancel discards and Done only updates the editor draft',
    (tester) async {
      await host(tester);
      await open(tester);
      await tester.enterText(search(), 'TAG 6');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-tag-16')));
      await tester.pumpAndSettle();
      await tester.enterText(search(), 'tag 7');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-tag-17')));
      await tester.pumpAndSettle();
      expect(find.text('5 selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      expect(h.app.itemDraft!.values['tag_ids'], [10, 11, 12]);
      await open(tester);
      await tester.enterText(search(), 'tag 6');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-tag-16')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await settle(tester);
      expect(h.app.itemDraft!.values['tag_ids'], [10, 11, 12, 16]);
      expect(h.doc['items']['3']['tag_ids'], [10, 11, 12]);
      expect(h.adapter.writes, 0);
    },
  );

  testWidgets(
    'a changed tag collection cannot apply a stale picker selection',
    (tester) async {
      await host(tester);
      await open(tester);
      await tester.enterText(search(), 'tag 6');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-tag-16')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => h.app.dispatch({'op': 'add_tag', 'name': 'New collection tag'}),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await settle(tester);
      expect(h.app.itemDraft!.values['tag_ids'], [10, 11, 12]);
      expect(
        find.textContaining('Tags changed while selecting'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'short narrow large-text picker keeps search, choices and Done reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 500);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 140);
      addTearDown(tester.view.reset);
      await host(tester, scale: 2);
      await tester.ensureVisible(find.text('Select other…'));
      await open(tester);
      await tester.enterText(search(), 'tag 6');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pick-tag-16')));
      await tester.tap(find.byKey(const ValueKey('pick-tag-16')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Done'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await settle(tester);
      expect(h.app.itemDraft!.values['tag_ids'], contains(16));
      expect(tester.takeException(), isNull);
    },
  );
}
