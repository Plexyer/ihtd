import 'dart:convert';
import 'dart:io';

import 'package:app/services/item_draft.dart';
import 'package:app/ui/sort_settings.dart';
import 'package:app/ui/item_drag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';

class SortHarness extends DraftHarness {
  SortHarness() : super(memoryDrafts: true);
  @override
  Future<String> command(String input) async {
    final op = jsonDecode(input) as Map<String, dynamic>;
    if (![
      'set_sort',
      'preview_sorted_move',
      'apply_sorted_move',
    ].contains(op['op'])) {
      return super.command(input);
    }
    commands.add(op);
    var data = <String, dynamic>{};
    if (op['op'] == 'set_sort') {
      (doc['views']['${op['view_id']}'] as Map).putIfAbsent(
        'sorting',
        () => <String, dynamic>{},
      );
      doc['views']['${op['view_id']}']['sorting']['${op['parent'] ?? 0}'] =
          op['sort'];
      doc['revision']++;
      await File(working).writeAsString(jsonEncode(doc));
    } else if (op['op'] == 'preview_sorted_move') {
      data = {
        'request': op['request'],
        'revision': doc['revision'],
        'digest': 'candidate',
        'switched_to_manual': true,
      };
    } else {
      doc['root_order'] = [3, 2];
      doc['revision']++;
      await File(working).writeAsString(jsonEncode(doc));
    }
    return jsonEncode({'ok': true, 'snapshot': snapshot(), 'data': data});
  }
}

void main() {
  late SortHarness h;
  setUp(() async {
    h = SortHarness();
    await h.initialize();
  });
  tearDown(() async {
    await h.dispose();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> host(WidgetTester tester, {int? parent}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSortSettings(context, h.app, parent: parent),
              child: const Text('Open sorting'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sorting'));
    await settle(tester);
  }

  Future<void> selectMode(WidgetTester tester, String title) async {
    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  testWidgets('sort Save/Cancel are per-view and do not commit an item draft', (
    tester,
  ) async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'Private notes');
    await host(tester, parent: 2);
    expect(
      tester
          .widget<DropdownButtonFormField<bool>>(
            find.byWidgetPredicate((w) => w is DropdownButtonFormField<bool>),
          )
          .onChanged,
      isNull,
    );
    await selectMode(tester, 'Priority');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(h.commands.where((c) => c['op'] == 'set_sort'), isEmpty);
    await tester.tap(find.text('Open sorting'));
    await settle(tester);
    await selectMode(tester, 'Due date');
    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<bool>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descending').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Save sorting')));
    await settle(tester);
    final saved = h.commands.lastWhere((c) => c['op'] == 'set_sort');
    expect(saved['parent'], 2);
    expect(saved['view_id'], 1);
    expect(saved['sort'], {'mode': 'due_date', 'descending': true});
    expect(h.app.itemDraft!.values['notes'], 'Private notes');
    expect(h.doc['items']['3']['notes'], 'Saved notes');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('Keep editing and queued view/tab changes prevent a move', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'Draft');
    h.app.chooseDraftExit = (_, _) async => DraftExitChoice.keepEditing;
    final owner = h.app.editIdentity;
    expect(
      await h.app.moveOccurrence(
        owner: owner,
        view: 1,
        completed: false,
        sourcePath: '3',
        destinationPath: '',
        before: 2,
        reorder: true,
      ),
      false,
    );
    expect(h.commands.where((c) => c['op'] == 'preview_sorted_move'), isEmpty);
    await h.app.discardItemDraft();
    h.app.busy = true;
    final waiting = h.app.dispatch(
      {'op': 'apply_sorted_move', 'plan': {}},
      expectedDocument: owner,
      expectedOutline: (viewId: 1, completed: false),
    );
    h.app.completedOnly = true;
    h.app.busy = false;
    expect(await waiting, isNull);
    expect(h.commands.where((c) => c['op'] == 'apply_sorted_move'), isEmpty);
    expect(h.app.error, contains('completion tab changed'));
  });
  testWidgets(
    'insertion drop carries paths and paints an indicator while dragging',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: h.app,
              builder: (_, _) => Column(
                children: [
                  PlacementRow(
                    app: h.app,
                    row: const {'id': 3, 'path': '3', 'depth': 0},
                    child: const SizedBox(
                      height: 64,
                      width: double.infinity,
                      child: Text('Source'),
                    ),
                  ),
                  PlacementRow(
                    app: h.app,
                    row: const {'id': 2, 'path': '2', 'depth': 0},
                    endPaths: const [''],
                    child: const SizedBox(
                      height: 64,
                      width: double.infinity,
                      child: Text('Target'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('drag-3'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(h.app.draggingItem, true);
      expect(find.byKey(const ValueKey('after-root')), findsOneWidget);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('before-2'))),
      );
      await tester.pump();
      await tester.runAsync(gesture.up);
      await settle(tester);
      expect(h.app.draggingItem, false);
      final request =
          h.commands.lastWhere(
                (c) => c['op'] == 'preview_sorted_move',
              )['request']
              as Map;
      expect(request['source_path'], [3]);
      expect(request['destination_path'], isEmpty);
      expect(request['before'], 2);
      expect(request['reorder'], true);
      expect(
        h.commands.where((c) => c['op'] == 'apply_sorted_move'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('same-UUID different working copy cannot accept an old drag', () async {
    final source = ItemPlacement(h.app.editIdentity, 1, false, '3', 3, null);
    h.working = '${h.working}.copy';
    await h.app.dispatch({'op': 'snapshot'});
    final target = ItemDropTarget(
      app: h.app,
      before: 2,
      reorder: true,
      child: const SizedBox(),
    );
    expect(target.accepts(source), false);
  });
  testWidgets('short narrow large-text sort dialog actions stay reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSortSettings(context, h.app),
              child: const Text('Open sorting'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sorting'));
    await settle(tester);
    await tester.ensureVisible(find.text('Save sorting'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
